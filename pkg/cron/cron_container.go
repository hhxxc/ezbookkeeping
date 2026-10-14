package cron

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-co-op/gocron/v2"

	"github.com/mayswind/ezbookkeeping/pkg/core"
	"github.com/mayswind/ezbookkeeping/pkg/errs"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"github.com/mayswind/ezbookkeeping/pkg/services"
	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

// CronJobSchedulerContainer contains the current cron job scheduler
type CronJobSchedulerContainer struct {
	scheduler        gocron.Scheduler
	allJobs          []*CronJob
	allJobsMap       map[string]*CronJob
	allGocronJobsMap map[string]gocron.Job
}

// Initialize a cron job scheduler container singleton instance
var (
	Container = &CronJobSchedulerContainer{
		allJobsMap:       make(map[string]*CronJob),
		allGocronJobsMap: make(map[string]gocron.Job),
	}
)

// InitializeCronJobSchedulerContainer initializes the cron job scheduler according to the config
func InitializeCronJobSchedulerContainer(ctx core.Context, config *settings.Config, startScheduler bool) error {
	var err error

	Container.scheduler, err = gocron.NewScheduler(
		gocron.WithLocation(time.Local),
		gocron.WithLogger(NewGocronLoggerAdapter()),
	)

	if err != nil {
		return err
	}

	Container.registerAllJobs(ctx, config)

	if startScheduler {
		Container.scheduler.Start()
	}

	return nil
}

// GetAllJobs returns all the cron jobs
func (c *CronJobSchedulerContainer) GetAllJobs() []*CronJob {
	return c.allJobs
}

// SyncRunJobNow runs the specified cron job synchronously now
func (c *CronJobSchedulerContainer) SyncRunJobNow(jobName string) error {
	if jobName == "" {
		return errs.ErrCronJobNameIsEmpty
	}

	job := c.allJobsMap[jobName]

	if job == nil {
		return errs.ErrCronJobNotExistsOrNotEnabled
	}

	gocronJob := c.allGocronJobsMap[jobName]

	if gocronJob == nil {
		return errs.ErrCronJobNotExistsOrNotEnabled
	}

	job.doRun()
	return nil
}

func (c *CronJobSchedulerContainer) registerAllJobs(ctx core.Context, config *settings.Config) {
	if config.EnableRemoveExpiredTokens {
		Container.registerIntervalJob(ctx, RemoveExpiredTokensJob)
	}

	if config.EnableCreateScheduledTransaction {
		appriseURL := config.NotifyAppriseURL
		CreateScheduledTransactionJob.Run = func(c *core.CronContext) error {
			count, details, err := services.Transactions.CreateScheduledTransactions(c, time.Now().Unix(), c.GetInterval())
			if err == nil && count > 0 && appriseURL != "" {
				notifyAppriseAsync(appriseURL, "周期账单已自动记账",
					fmt.Sprintf("已按周期模板自动记入 %d 笔账单：\n%s", count, details))
			}
			return err
		}
		Container.registerIntervalJob(ctx, CreateScheduledTransactionJob)
	}
}

func (c *CronJobSchedulerContainer) registerIntervalJob(ctx core.Context, job *CronJob) {
	gocronJob, err := c.scheduler.NewJob(
		job.Period.ToJobDefinition(),
		gocron.NewTask(job.doRun),
		gocron.WithName(job.Name),
		gocron.WithSingletonMode(gocron.LimitModeReschedule),
	)

	if err == nil {
		c.allJobs = append(c.allJobs, job)
		c.allJobsMap[job.Name] = job
		c.allGocronJobsMap[job.Name] = gocronJob
		log.Infof(ctx, "[cron_container.registerJob] job \"%s\" has been registered", job.Name)
		log.Debugf(ctx, "[cron_container.registerJob] job \"%s\" gocron id is %s", job.Name, gocronJob.ID())
	} else {
		log.Errorf(ctx, "[cron_container.registerJob] job \"%s\" cannot be been registered, because %s", job.Name, err.Error())
	}
}

// notifyAppriseAsync 异步推送 Apprise 通知（NAS 本机 Apprise API），失败仅记日志不重试
func notifyAppriseAsync(url string, title string, body string) {
	go func() {
		payload, err := json.Marshal(map[string]string{
			"title": title,
			"body":  body,
			"type":  "info",
		})
		if err != nil {
			return
		}
		req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(payload))
		if err != nil {
			return
		}
		req.Header.Set("Content-Type", "application/json")
		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			log.Warnf(nil, "[cron.notifyAppriseAsync] failed to send apprise notification, because %s", err.Error())
			return
		}
		defer resp.Body.Close()
		log.Infof(nil, "[cron.notifyAppriseAsync] apprise notification sent, status %d", resp.StatusCode)
	}()
}
