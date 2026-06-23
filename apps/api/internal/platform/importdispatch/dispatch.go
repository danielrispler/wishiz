// Package importdispatch hands a freshly-enqueued product import to the scraper
// service out-of-band via Google Cloud Tasks. The api role uses it so the user's
// enqueue request returns immediately while the (cold-start-tolerant) scraper
// processes the import behind an OIDC-authenticated task with built-in retries.
package importdispatch

import (
	"context"
	"fmt"
	"strings"

	cloudtasks "cloud.google.com/go/cloudtasks/apiv2"
	taskspb "cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
)

// Config configures the Cloud Tasks dispatcher.
type Config struct {
	// QueuePath is the fully-qualified queue: projects/P/locations/L/queues/Q.
	QueuePath string
	// ScraperBaseURL is the scraper service base URL; the task targets
	// <ScraperBaseURL>/internal/imports/<id>/process.
	ScraperBaseURL string
	// Audience is the OIDC token audience. For Cloud Run it must equal the
	// receiving service's base URL.
	Audience string
	// InvokerSA is the service-account email Cloud Tasks mints the OIDC token as;
	// it must hold run.invoker on the scraper service.
	InvokerSA string
}

// CloudTasks dispatches imports through a Cloud Tasks queue. It implements
// productimports/application.Dispatcher.
type CloudTasks struct {
	client *cloudtasks.Client
	cfg    Config
}

// New builds a Cloud Tasks dispatcher using Application Default Credentials.
func New(ctx context.Context, cfg Config) (*CloudTasks, error) {
	if strings.TrimSpace(cfg.QueuePath) == "" {
		return nil, fmt.Errorf("import dispatch: queue path is required")
	}
	if strings.TrimSpace(cfg.ScraperBaseURL) == "" {
		return nil, fmt.Errorf("import dispatch: scraper base url is required")
	}
	client, err := cloudtasks.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("create cloud tasks client: %w", err)
	}
	return &CloudTasks{client: client, cfg: cfg}, nil
}

// Dispatch creates a Cloud Task that POSTs to the scraper's process route for
// the given job, authenticated with an OIDC token.
func (d *CloudTasks) Dispatch(ctx context.Context, jobID string) error {
	url := strings.TrimRight(d.cfg.ScraperBaseURL, "/") + "/internal/imports/" + jobID + "/process"

	var oidc *taskspb.OidcToken
	if d.cfg.InvokerSA != "" {
		oidc = &taskspb.OidcToken{
			ServiceAccountEmail: d.cfg.InvokerSA,
			Audience:            d.cfg.Audience,
		}
	}

	req := &taskspb.CreateTaskRequest{
		Parent: d.cfg.QueuePath,
		Task: &taskspb.Task{
			MessageType: &taskspb.Task_HttpRequest{
				HttpRequest: &taskspb.HttpRequest{
					HttpMethod: taskspb.HttpMethod_POST,
					Url:        url,
				},
			},
		},
	}
	if oidc != nil {
		req.Task.GetHttpRequest().AuthorizationHeader = &taskspb.HttpRequest_OidcToken{OidcToken: oidc}
	}

	if _, err := d.client.CreateTask(ctx, req); err != nil {
		return fmt.Errorf("create cloud task for job %s: %w", jobID, err)
	}
	return nil
}

// Close releases the underlying Cloud Tasks client.
func (d *CloudTasks) Close() error {
	return d.client.Close()
}
