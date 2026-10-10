package api

import (
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/log"
)

// GitHubProxyApi represents github proxy api
type GitHubProxyApi struct{}

// Initialize a github proxy api singleton instance
var (
	GitHubProxy = &GitHubProxyApi{}
)

const githubDownloadProxiedUrlParam = "url"
const githubReleaseDownloadPrefix = "https://github.com/"

// 国内网络直连 GitHub release-assets 常被墙，NAS 侧同样不通（实测直连 ~11s 失败）。
// 直连失败后依次回退社区镜像前缀；镜像临时失效只影响本次下载（客户端会换其他
// 候选源），不影响正确性。
var githubDownloadMirrorPrefixes = []string{
	"https://ghfast.top/",
	"https://gh-proxy.com/",
}

// IPA 体量为 MB 级。不做整体 Client.Timeout（慢源传完即可），但传输层各阶段
// 收紧：拨号/握手各 10s、响应头 45s——被墙的源快速失败，尽快轮到下一个源；
// 体量上限由 LimitReader 控制。
var githubDownloadClient = &http.Client{
	Transport: &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           (&net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 45 * time.Second,
		IdleConnTimeout:       60 * time.Second,
	},
}

// githubProxyMaxDownloadSize 限制单次代理下载上限，防止镜像返回异常响应拖爆内存
const githubProxyMaxDownloadSize = 100 << 20

// githubProxyCacheKeepCount 磁盘缓存最多保留的文件数（每个 IPA 约 2~5MB）
const githubProxyCacheKeepCount = 10

// GitHubDownloadProxyHandler proxies a download from a GitHub release URL.
//
// 带磁盘缓存（data/nestkeep/proxy-cache/，与数据卷同挂载点、重建容器不丢）：
// 首次请求从 GitHub（或镜像）拉取并落盘，之后直接回本地文件。客户端（App/网页壳）
// 会校验内容为 zip（IPA）后使用，错误响应会被当作候选源失败处理。
func (a *GitHubProxyApi) GitHubDownloadProxyHandler(c *core.WebContext) {
	downloadUrl := c.Query(githubDownloadProxiedUrlParam)

	if downloadUrl == "" || !strings.HasPrefix(downloadUrl, githubReleaseDownloadPrefix) {
		c.String(http.StatusBadRequest, "invalid download url")
		return
	}

	cachePath := githubProxyCachePath(downloadUrl)

	if info, err := os.Stat(cachePath); err == nil && info.Size() > 0 {
		c.Header("Content-Disposition", "attachment; filename="+githubProxyFileName(downloadUrl))
		http.ServeFile(c.Writer, c.Request, cachePath)
		return
	}

	data, err := fetchFromGithubWithMirrors(downloadUrl)

	if err != nil {
		log.Warnf(c, "[github_proxy] failed to fetch %s: %s", downloadUrl, err.Error())
		c.String(http.StatusBadGateway, "upstream fetch failed")
		return
	}

	if err := saveGithubProxyCache(downloadUrl, data); err != nil {
		log.Warnf(c, "[github_proxy] failed to save cache for %s: %s", downloadUrl, err.Error())
		// 缓存写失败只影响下次速度，不阻断本次下发
	}

	c.Header("Content-Disposition", "attachment; filename="+githubProxyFileName(downloadUrl))
	c.Data(http.StatusOK, "application/octet-stream", data)
}

// fetchFromGithubWithMirrors 依次尝试 GitHub 直连与镜像前缀，返回第一个
// 「HTTP 200 且内容为 zip（IPA 头 PK）」的响应体；全部失败返回最后一个错误
func fetchFromGithubWithMirrors(downloadUrl string) ([]byte, error) {
	urls := make([]string, 0, 1+len(githubDownloadMirrorPrefixes))
	urls = append(urls, downloadUrl)
	for i := 0; i < len(githubDownloadMirrorPrefixes); i++ {
		urls = append(urls, githubDownloadMirrorPrefixes[i]+downloadUrl)
	}

	var lastErr error = errors.New("no source available")

	for _, u := range urls {
		resp, err := githubDownloadClient.Get(u)

		if err != nil {
			lastErr = err
			continue
		}

		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			lastErr = errors.New("upstream status " + resp.Status)
			continue
		}

		data, err := io.ReadAll(io.LimitReader(resp.Body, githubProxyMaxDownloadSize+1))
		resp.Body.Close()

		if err != nil {
			lastErr = err
			continue
		}

		// IPA 是 zip 包；镜像可能返回错误页/空响应，用文件头挡掉
		if len(data) < 2 || data[0] != 0x50 || data[1] != 0x4B {
			lastErr = errors.New("downloaded content is not a valid IPA")
			continue
		}

		return data, nil
	}

	return nil, lastErr
}

func githubProxyCachePath(downloadUrl string) string {
	sum := sha1.Sum([]byte(downloadUrl))
	return filepath.Join(nestKeepDataDir(), "proxy-cache", hex.EncodeToString(sum[:])+".ipa")
}

// githubProxyFileName 从 GitHub 直链里取资源文件名（Content-Disposition 用），
// 取不到时回退 nestkeep.ipa
func githubProxyFileName(downloadUrl string) string {
	name := downloadUrl
	if idx := strings.LastIndex(name, "/"); idx >= 0 {
		name = name[idx+1:]
	}
	if idx := strings.IndexAny(name, "?#"); idx >= 0 {
		name = name[:idx]
	}
	if name == "" {
		name = "nestkeep.ipa"
	}
	return name
}

// saveGithubProxyCache 原子写入缓存文件（临时文件 + rename），并裁剪缓存数量
func saveGithubProxyCache(downloadUrl string, data []byte) error {
	dir := filepath.Join(nestKeepDataDir(), "proxy-cache")

	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	tmpFile, err := os.CreateTemp(dir, "tmp-*")

	if err != nil {
		return err
	}

	tmpName := tmpFile.Name()

	if _, err := tmpFile.Write(data); err != nil {
		tmpFile.Close()
		os.Remove(tmpName)
		return err
	}

	if err := tmpFile.Close(); err != nil {
		os.Remove(tmpName)
		return err
	}

	if err := os.Rename(tmpName, githubProxyCachePath(downloadUrl)); err != nil {
		os.Remove(tmpName)
		return err
	}

	githubProxyCleanCache(dir, githubProxyCacheKeepCount)
	return nil
}

// githubProxyCleanCache 按修改时间只保留最近 keep 个缓存文件，失败静默忽略
func githubProxyCleanCache(dir string, keep int) {
	entries, err := os.ReadDir(dir)

	if err != nil {
		return
	}

	type cacheFile struct {
		path    string
		modTime time.Time
	}

	files := make([]cacheFile, 0, len(entries))

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		info, err := entry.Info()

		if err != nil {
			continue
		}

		files = append(files, cacheFile{path: filepath.Join(dir, entry.Name()), modTime: info.ModTime()})
	}

	if len(files) <= keep {
		return
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i].modTime.After(files[j].modTime)
	})

	for i := keep; i < len(files); i++ {
		os.Remove(files[i].path)
	}
}
