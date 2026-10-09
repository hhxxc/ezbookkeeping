package middlewares

import (
	"bytes"
	stdgzip "compress/gzip"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/andybalholm/brotli"
	gzipmw "github.com/gin-contrib/gzip"
	"github.com/gin-gonic/gin"
)

func newTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(Brotli(5))
	r.Use(gzipmw.Gzip(gzipmw.DefaultCompression,
		gzipmw.WithExcludedExtensions(CompressExcludedExtensions),
		gzipmw.WithCustomShouldCompressFn(ShouldGzipCompress),
	))
	r.GET("/api/test", func(c *gin.Context) {
		c.String(http.StatusOK, "hello world hello world hello world")
	})
	r.GET("/img/test.png", func(c *gin.Context) {
		c.String(http.StatusOK, "fakepng")
	})
	r.GET("/api/bad", func(c *gin.Context) {
		c.String(http.StatusBadRequest, "bad request")
	})
	return r
}

func decode(t *testing.T, encoding, body string) string {
	t.Helper()
	switch encoding {
	case "br":
		rd := brotli.NewReader(bytes.NewReader([]byte(body)))
		out, err := io.ReadAll(rd)
		if err != nil {
			t.Fatalf("brotli 解码失败: %v", err)
		}
		return string(out)
	case "gzip":
		rd, err := stdgzip.NewReader(bytes.NewReader([]byte(body)))
		if err != nil {
			t.Fatalf("gzip 解码失败: %v", err)
		}
		out, err := io.ReadAll(rd)
		if err != nil {
			t.Fatalf("gzip 解码失败: %v", err)
		}
		return string(out)
	default:
		return body
	}
}

func do(t *testing.T, r *gin.Engine, path, acceptEncoding string) (*httptest.ResponseRecorder, string) {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	// httptest.NewRequest 默认带 Accept-Encoding: gzip，必须显式覆盖
	req.Header.Set("Accept-Encoding", acceptEncoding)
	r.ServeHTTP(w, req)
	return w, w.Header().Get("Content-Encoding")
}

func TestBrotliPreferredWhenClientSupportsBr(t *testing.T) {
	r := newTestRouter()
	w, enc := do(t, r, "/api/test", "gzip, deflate, br")
	if enc != "br" {
		t.Fatalf("期望 Content-Encoding=br, 实际 %q", enc)
	}
	if got := decode(t, "br", w.Body.String()); got != "hello world hello world hello world" {
		t.Fatalf("内容不对: %q", got)
	}
	if w.Header().Get("Vary") != "Accept-Encoding" {
		t.Fatalf("缺 Vary: %v", w.Header())
	}
}

func TestGzipFallbackWhenNoBr(t *testing.T) {
	r := newTestRouter()
	w, enc := do(t, r, "/api/test", "gzip, deflate")
	if enc != "gzip" {
		t.Fatalf("期望回退 gzip, 实际 %q", enc)
	}
	if got := decode(t, "gzip", w.Body.String()); got != "hello world hello world hello world" {
		t.Fatalf("内容不对: %q", got)
	}
}

func TestNoCompressionWithoutAcceptEncoding(t *testing.T) {
	r := newTestRouter()
	_, enc := do(t, r, "/api/test", "")
	if enc != "" {
		t.Fatalf("不该有压缩, 实际 %q", enc)
	}
}

func TestExcludedExtensionNotCompressed(t *testing.T) {
	r := newTestRouter()
	_, enc := do(t, r, "/img/test.png", "gzip, br")
	if enc != "" {
		t.Fatalf("png 不应压缩, 实际 %q", enc)
	}
}

func TestErrorResponseNotCompressed(t *testing.T) {
	r := newTestRouter()
	w, enc := do(t, r, "/api/bad", "gzip, br")
	if enc != "" {
		t.Fatalf("错误响应不应压缩, 实际 %q", enc)
	}
	if w.Code != http.StatusBadRequest {
		t.Fatalf("状态码不对: %d", w.Code)
	}
	if w.Body.String() != "bad request" {
		t.Fatalf("错误内容不对: %q", w.Body.String())
	}
}
