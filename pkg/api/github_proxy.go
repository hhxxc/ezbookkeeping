package api

import (
	"io"
	"net/http"
	"strings"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
)

// GitHubProxyApi represents github proxy api
type GitHubProxyApi struct{}

// Initialize a github proxy api singleton instance
var (
	GitHubProxy = &GitHubProxyApi{}
)

const githubDownloadProxiedUrlParam = "url"
const githubReleaseDownloadPrefix = "https://github.com/"

// GitHubDownloadProxyHandler proxies a download from a GitHub URL
func (a *GitHubProxyApi) GitHubDownloadProxyHandler(c *core.WebContext) *errs.Error {
	downloadUrl := c.Query(githubDownloadProxiedUrlParam)

	if downloadUrl == "" || !strings.HasPrefix(downloadUrl, githubReleaseDownloadPrefix) {
		return errs.NewNormalError(errs.NormalSubcategoryGlobal, 0, http.StatusBadRequest, "invalid download url")
	}

	resp, err := http.Get(downloadUrl)
	if err != nil {
		return errs.NewNormalError(errs.NormalSubcategoryGlobal, 1, http.StatusInternalServerError, "operation failed")
	}
	defer resp.Body.Close()

	c.Header("Content-Disposition", "attachment; filename=nestkeep.ipa")
	c.Status(http.StatusOK)
	io.Copy(c.Writer, resp.Body)
	return nil
}
