package duplicatechecker

import (
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/mayswind/ezbookkeeping/pkg/datastore"
	"github.com/mayswind/ezbookkeeping/pkg/log"
	"xorm.io/xorm"

	"github.com/mayswind/ezbookkeeping/pkg/settings"
)

// DatabaseDuplicateCheckData represents the persistent key-value record for duplicate checking
type DatabaseDuplicateCheckData struct {
	CheckKey         string `xorm:"PK VARCHAR(255) NOT NULL"`
	Remark           string `xorm:"VARCHAR(255) NOT NULL DEFAULT ''"`
	ExpireAtUnixTime int64  `xorm:"BIGINT NOT NULL"`
}

// DatabaseDuplicateChecker represents database-backed duplicate checker (persistent across restarts)
type DatabaseDuplicateChecker struct {
	store *datastore.DataStore

	defaultExpiration time.Duration

	mutex sync.Mutex
}

// NewDatabaseDuplicateChecker returns a new database-backed duplicate checker
func NewDatabaseDuplicateChecker(config *settings.Config, store *datastore.DataStore) (*DatabaseDuplicateChecker, error) {
	checker := &DatabaseDuplicateChecker{
		store:             store,
		defaultExpiration: config.DuplicateSubmissionsIntervalDuration,
	}

	return checker, nil
}

// SyncTable creates or updates the backing table structure
func (c *DatabaseDuplicateChecker) SyncTable() error {
	return c.store.SyncStructs(new(DatabaseDuplicateCheckData))
}

// GetSubmissionRemark returns whether the same submission has been processed and related remark
func (c *DatabaseDuplicateChecker) GetSubmissionRemark(checkerType DuplicateCheckerType, uid int64, identification string) (bool, string) {
	return c.getRemark(c.getKey(checkerType, uid, identification))
}

// SetSubmissionRemark saves the identification and remark to database
func (c *DatabaseDuplicateChecker) SetSubmissionRemark(checkerType DuplicateCheckerType, uid int64, identification string, remark string) {
	c.SetSubmissionRemarkWithCustomExpiration(checkerType, uid, identification, remark, c.defaultExpiration)
}

// SetSubmissionRemarkWithCustomExpiration saves the identification and remark to database with custom expiration time
func (c *DatabaseDuplicateChecker) SetSubmissionRemarkWithCustomExpiration(checkerType DuplicateCheckerType, uid int64, identification string, remark string, expiration time.Duration) {
	err := c.store.DoTransaction(0, nil, func(sess *xorm.Session) error {
		return c.upsertRemark(sess, c.getKey(checkerType, uid, identification), remark, expiration)
	})

	if err != nil {
		log.Errorf(nil, "[duplicatechecker] failed to save duplicate check remark, because %s", err.Error())
	}
}

// RemoveSubmissionRemark removes the identification and remark in database
func (c *DatabaseDuplicateChecker) RemoveSubmissionRemark(checkerType DuplicateCheckerType, uid int64, identification string) {
	err := c.store.DoTransaction(0, nil, func(sess *xorm.Session) error {
		_, err := sess.Where("check_key=?", c.getKey(checkerType, uid, identification)).Delete(new(DatabaseDuplicateCheckData))
		return err
	})

	if err != nil {
		log.Errorf(nil, "[duplicatechecker] failed to remove duplicate check remark, because %s", err.Error())
	}
}

// GetOrSetCronJobRunningInfo returns the running info when the cron job is running or saves the running info
func (c *DatabaseDuplicateChecker) GetOrSetCronJobRunningInfo(jobName string, runningInfo string, runningInterval time.Duration) (bool, string) {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	key := c.getKey(DUPLICATE_CHECKER_TYPE_BACKGROUND_CRON_JOB, 0, jobName)
	found, remark := c.getRemark(key)

	if found {
		return true, remark
	}

	expiration := runningInterval

	if expiration > 1*time.Second {
		expiration = expiration - 1*time.Second
	}

	c.SetSubmissionRemarkWithCustomExpiration(DUPLICATE_CHECKER_TYPE_BACKGROUND_CRON_JOB, 0, jobName, runningInfo, expiration)

	return false, ""
}

// RemoveCronJobRunningInfo removes the running info of the cron job
func (c *DatabaseDuplicateChecker) RemoveCronJobRunningInfo(jobName string) {
	c.RemoveSubmissionRemark(DUPLICATE_CHECKER_TYPE_BACKGROUND_CRON_JOB, 0, jobName)
}

// GetFailureCount returns the failure count of the specified failure key
func (c *DatabaseDuplicateChecker) GetFailureCount(failureKey string) uint32 {
	found, remark := c.getRemark(c.getKey(DUPLICATE_CHECKER_TYPE_FAILURE_CHECK, 0, failureKey))

	if !found {
		return 0
	}

	count, err := strconv.ParseUint(remark, 10, 32)

	if err != nil {
		return 0
	}

	return uint32(count)
}

// IncreaseFailureCount increases the failure count of the specified failure key
func (c *DatabaseDuplicateChecker) IncreaseFailureCount(failureKey string) uint32 {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	key := c.getKey(DUPLICATE_CHECKER_TYPE_FAILURE_CHECK, 0, failureKey)
	newCount := uint32(1)
	found, remark := c.getRemark(key)

	if found {
		count, err := strconv.ParseUint(remark, 10, 32)

		if err == nil {
			newCount = uint32(count) + 1
		}
	}

	c.SetSubmissionRemarkWithCustomExpiration(DUPLICATE_CHECKER_TYPE_FAILURE_CHECK, 0, failureKey, strconv.FormatUint(uint64(newCount), 10), 1*time.Minute)

	return newCount
}

// CleanupExpiredKeys removes expired records (called periodically)
func (c *DatabaseDuplicateChecker) CleanupExpiredKeys() {
	err := c.store.DoTransaction(0, nil, func(sess *xorm.Session) error {
		_, err := sess.Where("expire_at_unix_time<?", time.Now().Unix()).Delete(new(DatabaseDuplicateCheckData))
		return err
	})

	if err != nil {
		log.Errorf(nil, "[duplicatechecker] failed to cleanup expired duplicate check keys, because %s", err.Error())
	}
}

func (c *DatabaseDuplicateChecker) getKey(checkerType DuplicateCheckerType, uid int64, identification string) string {
	return fmt.Sprintf("%d|%d|%s", checkerType, uid, identification)
}

func (c *DatabaseDuplicateChecker) getRemark(key string) (bool, string) {
	var found bool
	var remark string

	err := c.store.DoTransaction(0, nil, func(sess *xorm.Session) error {
		data := &DatabaseDuplicateCheckData{}
		exists, err := sess.Where("check_key=?", key).Get(data)

		if err != nil {
			return err
		}

		if exists && data.ExpireAtUnixTime > time.Now().Unix() {
			found = true
			remark = data.Remark
		}

		return nil
	})

	if err != nil {
		log.Errorf(nil, "[duplicatechecker] failed to get duplicate check remark, because %s", err.Error())
		return false, ""
	}

	return found, remark
}

func (c *DatabaseDuplicateChecker) upsertRemark(sess *xorm.Session, key string, remark string, expiration time.Duration) error {
	_, err := sess.Where("check_key=?", key).Delete(new(DatabaseDuplicateCheckData))

	if err != nil {
		return err
	}

	data := &DatabaseDuplicateCheckData{
		CheckKey:         key,
		Remark:           remark,
		ExpireAtUnixTime: time.Now().Add(expiration).Unix(),
	}

	_, err = sess.Insert(data)
	return err
}
