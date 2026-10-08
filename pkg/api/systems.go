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

// NestKeepIpaHandler 直接下发 NAS 上的 NestKeep IPA 文件（无鉴权）。
// 供手机在国内网络环境下从自有域名下载安装包，完全不依赖 github.com。
// 为避免路径穿越，只允许 data/nestkeep 目录下的 .ipa 文件。
func (a *SystemsApi) NestKeepIpaHandler(c *core.WebContext) {
	name := strings.TrimSpace(c.Param("name"))

	if name == "" || !strings.HasSuffix(strings.ToLower(name), ".ipa") ||
		strings.ContainsAny(name, "/\\") || strings.Contains(name, "..") {
		c.Status(http.StatusBadRequest)
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

