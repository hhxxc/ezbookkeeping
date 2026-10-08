package api

import (
	"net/http"
	"os"
	"path/filepath"

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

// nestKeepLatestFilePath 返回 NestKeep 更新描述文件 latest.json 的路径。
// 约定放在工作目录同级的 data 目录下（容器里 /ezbookkeeping/data/nestkeep/latest.json，
// 与数据卷同一挂载点，重建容器不丢）。
func nestKeepLatestFilePath(c *core.WebContext) string {
	workingDir, err := os.Getwd()
	if err != nil {
		workingDir = "."
	}
	return filepath.Join(workingDir, "data", "nestkeep", "latest.json")
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

