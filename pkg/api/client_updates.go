package api

import (
	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

// ClientUpdatesApi represents client update api
type ClientUpdatesApi struct {
	ApiUsingConfig
}

// Initialize a client updates api singleton instance
var (
	ClientUpdates = &ClientUpdatesApi{
		ApiUsingConfig: ApiUsingConfig{
			container: settings.Container,
		},
	}
)

// ClientUpdateInfo represents the client update information
type ClientUpdateInfo struct {
	LatestVersion  string `json:"latestVersion"`
	IpaDownloadUrl string `json:"ipaDownloadUrl,omitempty"`
}

// UpdateHandler returns the latest client update information
func (a *ClientUpdatesApi) UpdateHandler(c *core.WebContext) (any, *errs.Error) {
	config := a.CurrentConfig()

	result := &ClientUpdateInfo{
		LatestVersion:  core.Version,
		IpaDownloadUrl: config.IpaDownloadUrl,
	}

	return result, nil
}
