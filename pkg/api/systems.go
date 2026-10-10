package api

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
)

// SystemsApi represents system api
type SystemsApi struct{}

// Initialize a system api singleton instance
var (
	Systems = &SystemsApi{}
)

// VersionHandler returns the server version and commit hash
func (a *SystemsApi) VersionHandler(c *core.WebContext) (any, *errs.Error) {
	result := make(map[string]string)

	result["version"] = core.Version
	result["commitHash"] = core.CommitHash

	if core.BuildTime != "" {
		result["buildTime"] = core.BuildTime
	}

	return result, nil
}

// nestKeepDataDir 返回 NestKeep 相关文件的目录。
// 约定放在工作目录同级的 data/nestkeep 下（容器里 /ezbookkeeping/data/nestkeep/，
// 与数据卷同一挂载点，重建容器不丢）。
func nestKeepDataDir() string {
	workingDir, err := os.Getwd()
	if err != nil {
		workingDir = "."
	}
	return filepath.Join(workingDir, "data", "nestkeep")
}

// nestKeepLatestFilePath 返回 NestKeep 更新描述文件 latest.json 的路径。
func nestKeepLatestFilePath(c *core.WebContext) string {
	return filepath.Join(nestKeepDataDir(), "latest.json")
}

// nestKeepVariantLatestFilePath 返回指定变体（channel）的更新描述文件路径，
// 例如 latest-dev.json / latest-pro.json。
//
// 背景：原生 App 有多个变体（dev=巢记+ / pro=巢记Pro 等），Bundle ID 不同、
// 可同时安装。若共用一份 latest.json，各变体会互相提示「有新版本」并把对方
// 版本的包推给自己（跨变体覆盖安装会写入错误的 App）。故按变体分文件存储。
//
// channel 白名单校验，避免路径穿越。
func nestKeepVariantLatestFilePath(channel string) string {
	return filepath.Join(nestKeepDataDir(), "latest-"+channel+".json")
}

// isSafeNestKeepChannel 只允许字母、数字、连字符，防止 ../ 之类的路径穿越。
func isSafeNestKeepChannel(s string) bool {
	if s == "" || len(s) > 32 {
		return false
	}
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' {
			continue
		}
		return false
	}
	return true
}

// NestKeepLatestHandler 返回 NestKeep 原生 App 最新版本元信息（裸 JSON，不包统一信封）。
// App 端优先读此接口（走用户自己的域名，国内可达）；读不到时回退 GitHub API。
func (a *SystemsApi) NestKeepLatestHandler(c *core.WebContext) {
	filePath := nestKeepLatestFilePath(c)
	data, err := os.ReadFile(filePath)

	if err != nil {
		log.Warnf(c, "[systems.NestKeepLatestHandler] could not read %s: %s", filePath, err.Error())
		c.Status(http.StatusNotFound)
		return
	}

	c.Data(http.StatusOK, "application/json; charset=utf-8", data)
}

// NestKeepIpaHandler 直接下发 NAS 上的 NestKeep 文件（无鉴权）：
//   - *.ipa：安装包，供手机在国内网络环境下从自有域名下载，不依赖 github.com
//   - latest-<channel>.json：变体更新清单（gin 不支持段中间参数，
//     `latest-:channel.json` 的 :channel 捕获恒为空，故在 :name 兜底路由里解析文件名）
//
// 为避免路径穿越，只允许 data/nestkeep 目录下的这两类文件。
func (a *SystemsApi) NestKeepIpaHandler(c *core.WebContext) {
	name := strings.TrimSpace(c.Param("name"))
	lower := strings.ToLower(name)

	isIpa := strings.HasSuffix(lower, ".ipa")
	isVariantManifest := strings.HasPrefix(lower, "latest-") && strings.HasSuffix(lower, ".json")

	if name == "" || (!isIpa && !isVariantManifest) ||
		strings.ContainsAny(name, "/\\") || strings.Contains(name, "..") {
		c.Status(http.StatusBadRequest)
		return
	}

	// 变体清单：channel 从文件名解析（latest-pro.json -> pro），白名单校验后按变体路由语义返回
	if isVariantManifest {
		channel := name[len("latest-") : len(name)-len(".json")]

		if !isSafeNestKeepChannel(channel) {
			c.Status(http.StatusBadRequest)
			return
		}

		filePath := nestKeepVariantLatestFilePath(channel)
		data, err := os.ReadFile(filePath)

		if err != nil {
			// 变体清单缺失时回退到通用清单（兼容旧版发布脚本只写 latest.json 的情况）
			if legacy, legacyErr := os.ReadFile(nestKeepLatestFilePath(c)); legacyErr == nil {
				c.Data(http.StatusOK, "application/json; charset=utf-8", legacy)
				return
			}

			log.Warnf(c, "[systems.NestKeepIpaHandler] could not read %s: %s", filePath, err.Error())
			c.Status(http.StatusNotFound)
			return
		}

		c.Data(http.StatusOK, "application/json; charset=utf-8", data)
		return
	}

	filePath := filepath.Join(nestKeepDataDir(), filepath.Base(name))
	info, err := os.Stat(filePath)

	if err != nil || info.IsDir() {
		log.Warnf(c, "[systems.NestKeepIpaHandler] could not stat %s: %v", filePath, err)
		c.Status(http.StatusNotFound)
		return
	}

	c.Header("Content-Disposition", "attachment; filename=\""+filepath.Base(name)+"\"")
	c.File(filePath)
}

