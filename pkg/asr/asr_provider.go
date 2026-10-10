package asr

import "github.com/mayswind/ezbookkeeping/pkg/core"

// ASRProvider represents the automatic speech recognition provider interface
type ASRProvider interface {
	// Transcribe converts the given audio data into text
	Transcribe(c *core.WebContext, audioData []byte, contentType string) (string, error)
}
