package middlewares

import (
	"bufio"
	"io"
	"net"
	"net/http"
	"path/filepath"
	"strings"
	"sync"

	"github.com/andybalholm/brotli"
	"github.com/gin-gonic/gin"
)

const (
	headerAcceptEncoding  = "Accept-Encoding"
	headerContentEncoding = "Content-Encoding"
	headerVary            = "Vary"
	// compressHandledKey 存于 gin.Context，标记请求已由 brotli 中间件压缩
	compressHandledKey = "ezb_compress_handled"
)

// CompressHandledKey 返回标记请求已被 brotli 压缩的 gin.Context key，
// 供 gzip 中间件的 WithCustomShouldCompressFn 判断是否跳过
func CompressHandledKey() string {
	return compressHandledKey
}

// Brotli 压缩中间件。
//
// 仅当客户端 Accept-Encoding 含 "br" 时生效（brotli 比 gzip 再小 15~20%），
// 其余请求原样放行、交给链上后面的 gzip 中间件处理。
// 需与 gzip 中间件配合：gzip 侧用 WithCustomShouldCompressFn 跳过
// CompressHandledKey 已置位的请求，避免双重压缩。
func Brotli(quality int) gin.HandlerFunc {
	if quality < brotli.BestSpeed || quality > brotli.BestCompression {
		// 5 是 NAS（低功耗 CPU）上压缩比与耗时的平衡点；
		// 11 压缩比最好但单次响应要秒级，动态压缩不划算
		quality = 5
	}

	bwPool := sync.Pool{
		New: func() interface{} {
			w := brotli.NewWriterLevel(io.Discard, quality)
			return w
		},
	}

	return func(c *gin.Context) {
		if !shouldBrotliCompress(c.Request) {
			c.Next()
			return
		}

		bw := bwPool.Get().(*brotli.Writer)
		bw.Reset(c.Writer)

		c.Header(headerContentEncoding, "br")
		c.Writer.Header().Add(headerVary, headerAcceptEncoding)

		// 弱 ETag（W/ 前缀）允许压缩后共享，强 ETag 需转为弱 ETag
		if originalEtag := c.GetHeader("ETag"); originalEtag != "" && !strings.HasPrefix(originalEtag, "W/") {
			c.Header("ETag", "W/"+originalEtag)
		}

		// 标记本请求已由 brotli 压缩，gzip 中间件据此跳过
		c.Set(compressHandledKey, true)

		bww := &brotliResponseWriter{
			ResponseWriter: c.Writer,
			writer:         bw,
		}
		c.Writer = bww

		defer func() {
			if bww.status >= 400 || !bww.wrote {
				// 错误响应 / 没写过响应体（如 304、HEAD）：不落 brotli 收尾字节
				// 注意不能用 c.Writer.Size() 判断——brotli.Writer 内部缓冲，
				// Close 之前底层 writer 一个字节都没收到，Size() 恒为 -1
				bww.removeCompressHeaders()
				bw.Reset(io.Discard)
			}
			_ = bw.Close()
			bwPool.Put(bw)
		}()

		c.Next()
	}
}

// CompressExcludedExtensions 压缩排除的扩展名（brotli/gzip 共用）：
// 这些格式本身已压缩，二次压缩只费 CPU 不省体积
var CompressExcludedExtensions = []string{
	".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".mp4",
	".woff", ".woff2", ".ttf", ".eot", ".otf",
	".zip", ".gz", ".br", ".tgz", ".bz2", ".xz", ".7z", ".rar",
}

var compressExcludedSet = func() map[string]struct{} {
	set := make(map[string]struct{}, len(CompressExcludedExtensions))
	for _, ext := range CompressExcludedExtensions {
		set[ext] = struct{}{}
	}
	return set
}()

// ShouldGzipCompress 供 gzip 中间件的 WithCustomShouldCompressFn 使用。
// 注意：设置自定义 ShouldCompressFn 后，gin-contrib/gzip 的默认判断
// （Accept-Encoding 检查、扩展名排除等）会被整体覆盖，必须在这里补齐，
// 并额外跳过已由 brotli 中间件处理的请求。
func ShouldGzipCompress(c *gin.Context) bool {
	// 已由 brotli 压缩（Content-Encoding: br），gzip 直接跳过
	if c.GetBool(compressHandledKey) {
		return false
	}

	req := c.Request
	if strings.Contains(req.Header.Get("Connection"), "Upgrade") {
		return false
	}
	if !strings.Contains(req.Header.Get(headerAcceptEncoding), "gzip") {
		return false
	}
	if _, excluded := compressExcludedSet[filepath.Ext(req.URL.Path)]; excluded {
		return false
	}

	return true
}

func shouldBrotliCompress(req *http.Request) bool {
	// WebSocket 升级请求不压缩
	if strings.Contains(req.Header.Get("Connection"), "Upgrade") {
		return false
	}

	// 客户端必须声明支持 br
	if !strings.Contains(req.Header.Get(headerAcceptEncoding), "br") {
		return false
	}

	// 已压缩格式二次压缩只费 CPU 不省体积
	if _, excluded := compressExcludedSet[filepath.Ext(req.URL.Path)]; excluded {
		return false
	}

	return true
}

type brotliResponseWriter struct {
	gin.ResponseWriter
	writer   *brotli.Writer
	status   int
	statused bool
	// wrote 标记响应体是否经过本 writer（brotli.Writer 有内部缓冲，
	// 不能用底层 Size() 判断是否有响应体）
	wrote bool
}

func (b *brotliResponseWriter) WriteString(s string) (int, error) {
	return b.Write([]byte(s))
}

func (b *brotliResponseWriter) Write(data []byte) (int, error) {
	if !b.statused {
		b.status = b.ResponseWriter.Status()
	}

	// 错误响应不压缩
	if b.status >= 400 {
		b.removeCompressHeaders()
		return b.ResponseWriter.Write(data)
	}

	// 上游已设置其他 Content-Encoding（如 Range 请求、预压缩文件），透传不重复压缩
	if enc := b.Header().Get(headerContentEncoding); enc != "" && enc != "br" {
		b.removeCompressHeaders()
		return b.ResponseWriter.Write(data)
	}

	b.wrote = true
	return b.writer.Write(data)
}

func (b *brotliResponseWriter) WriteHeader(code int) {
	b.status = code
	b.statused = true
	b.ResponseWriter.WriteHeader(code)
}

func (b *brotliResponseWriter) Status() int {
	if b.statused {
		return b.status
	}
	return b.ResponseWriter.Status()
}

func (b *brotliResponseWriter) Flush() {
	_ = b.writer.Flush()
	b.ResponseWriter.Flush()
}

func (b *brotliResponseWriter) removeCompressHeaders() {
	b.Header().Del(headerContentEncoding)
	b.Header().Del(headerVary)
	b.Header().Del("ETag")
}

var (
	_ http.Hijacker = (*brotliResponseWriter)(nil)
)

func (b *brotliResponseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := b.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, http.ErrNotSupported
	}
	return hijacker.Hijack()
}
