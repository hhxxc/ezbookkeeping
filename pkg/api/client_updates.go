package api

import (
	"fmt"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
)

const ezbookkeepingIpaDownloadRepoUrl = "https://github.com/hhxxc/ezbookkeeping"

// ClientUpdatesApi represents client update api
type ClientUpdatesApi struct{}

// Initialize a client updates api singleton instance
var (
	ClientUpdates = &ClientUpdatesApi{}
)

// ClientUpdateInfo represents the client update information
type ClientUpdateInfo struct {
	LatestVersion  string `json:"latestVersion"`
	IpaDownloadUrl string `json:"ipaDownloadUrl,omitempty"`
	ReleaseNotes  string `json:"releaseNotes,omitempty"`
}

// UpdateHandler returns the latest client update information
func (a *ClientUpdatesApi) UpdateHandler(c *core.WebContext) (any, *errs.Error) {
	version := core.Version

	result := &ClientUpdateInfo{
		LatestVersion:  version,
		IpaDownloadUrl: fmt.Sprintf("%s/releases/download/v%s/nestkeep.ipa", ezbookkeepingIpaDownloadRepoUrl, version),
		ReleaseNotes:  fmt.Sprintf("%s/releases/tag/v%s", ezbookkeepingIpaDownloadRepoUrl, version),
	}

	return result, nil
}
