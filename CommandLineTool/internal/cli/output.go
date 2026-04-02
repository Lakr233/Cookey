package cli

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"cookey/internal/models"
)

func emitLoginOutput(output models.LoginOutput, mode requestMode, asJSON bool) error {
	if asJSON {
		return emit(output, true)
	}

	action := "Started"
	if mode == requestModeRefresh {
		action = "Refreshed"
	}

	fmt.Printf("  %s request  %s\n", action, output.RID)
	fmt.Printf("  Target URL       %s\n", output.TargetURL)
	expiresAt := time.Now().Add(time.Duration(output.TimeoutSeconds) * time.Second)
	fmt.Printf("  Expires in       %s (%s)\n\n", formatLoginTimeout(output.TimeoutSeconds), expiresAt.Format("15:04:05"))
	if output.ShowQR && output.QRText != "" {
		fmt.Print(output.QRText)
		if !strings.HasSuffix(output.QRText, "\n") {
			fmt.Println()
		}
	}
	if output.PairKey != "" {
		fmt.Printf("  Pair Key         %s-%s\n", output.PairKey[:4], output.PairKey[4:])
		fmt.Printf("  Deep Link        %s\n", output.PairKeyDeepLink)
	}
	if output.ShowQR {
		fmt.Println("  Scan or type the pair key in the Cookey app to continue.")
	} else {
		fmt.Println("  Open the Cookey app and type the pair key to continue.")
	}
	return nil
}

func emit(value any, asJSON bool) error {
	rendered, err := render(value, asJSON)
	if err != nil {
		return err
	}
	fmt.Println(rendered)
	return nil
}

func render(value any, asJSON bool) (string, error) {
	if asJSON {
		data, err := encodeJSON(value, true)
		if err != nil {
			return "", err
		}
		return strings.TrimRight(string(data), "\n"), nil
	}

	switch typed := value.(type) {
	case models.StatusSnapshot:
		return renderSnapshot(typed), nil
	case models.StatusSummary:
		return renderSummary(typed), nil
	case []models.StatusSnapshot:
		return renderSnapshotList(typed), nil
	case models.DeleteOutput:
		return renderDeleteOutput(typed), nil
	case models.CleanOutput:
		return renderCleanOutput(typed), nil
	case configView:
		return renderConfigView(typed), nil
	case configSetResult:
		return fmt.Sprintf("%s: %v", typed.Key, typed.Value), nil
	default:
		return fmt.Sprintf("%v", typed), nil
	}
}

func encodeJSON(value any, pretty bool) ([]byte, error) {
	if pretty {
		data, err := json.MarshalIndent(value, "", "  ")
		if err != nil {
			return nil, err
		}
		return append(data, '\n'), nil
	}
	return json.Marshal(value)
}

func renderSnapshotList(snapshots []models.StatusSnapshot) string {
	if len(snapshots) == 0 {
		return "No local requests found."
	}

	parts := make([]string, 0, len(snapshots))
	for _, snapshot := range snapshots {
		parts = append(parts, renderSnapshot(snapshot))
	}
	return strings.Join(parts, "\n\n")
}

func renderSnapshot(snapshot models.StatusSnapshot) string {
	lines := []string{
		"rid: " + snapshot.RID,
		"status: " + string(snapshot.Status),
	}

	if snapshot.PID != nil {
		lines = append(lines, fmt.Sprintf("pid: %d", *snapshot.PID))
	}
	if snapshot.TargetURL != nil {
		lines = append(lines, "target_url: "+*snapshot.TargetURL)
	}
	if snapshot.SessionPath != nil {
		lines = append(lines, "session_path: "+*snapshot.SessionPath)
	}
	if snapshot.UpdatedAt != nil {
		lines = append(lines, "updated_at: "+snapshot.UpdatedAt.Time.Format(time.RFC3339))
	}
	if snapshot.ServerURL != nil {
		lines = append(lines, "server_url: "+*snapshot.ServerURL)
	}
	if snapshot.ErrorMessage != nil {
		lines = append(lines, "error: "+*snapshot.ErrorMessage)
	}

	return strings.Join(lines, "\n")
}

func renderSummary(summary models.StatusSummary) string {
	lines := make([]string, 0, 4)
	if summary.LatestDaemon != nil {
		lines = append(lines, "latest_daemon:")
		lines = append(lines, renderSnapshot(*summary.LatestDaemon))
	}
	if summary.LatestSession != nil {
		lines = append(lines, "latest_session:")
		lines = append(lines, renderSnapshot(*summary.LatestSession))
	}
	if len(lines) == 0 {
		return "No local requests found."
	}
	return strings.Join(lines, "\n")
}

func deletedComponents(output models.DeleteOutput) []string {
	var parts []string
	if output.SessionDeleted {
		parts = append(parts, "session")
	}
	if output.DaemonDeleted {
		parts = append(parts, "daemon")
	}
	return parts
}

func renderDeleteOutput(output models.DeleteOutput) string {
	parts := deletedComponents(output)
	if len(parts) == 0 {
		return "rid: " + output.RID + "\ndeleted: none"
	}
	return "rid: " + output.RID + "\ndeleted: " + strings.Join(parts, ", ")
}

func renderCleanOutput(output models.CleanOutput) string {
	if len(output.Deleted) == 0 && len(output.Skipped) == 0 {
		return "No local requests found."
	}

	lines := make([]string, 0, len(output.Deleted)+len(output.Skipped)+2)
	if len(output.Deleted) > 0 {
		lines = append(lines, "deleted:")
		for _, item := range output.Deleted {
			parts := deletedComponents(item)
			lines = append(lines, "  "+item.RID+" ("+strings.Join(parts, ", ")+")")
		}
	}
	if len(output.Skipped) > 0 {
		lines = append(lines, "skipped_active:")
		for _, snapshot := range output.Skipped {
			lines = append(lines, "  "+snapshot.RID+" (status: "+string(snapshot.Status)+")")
		}
	}
	return strings.Join(lines, "\n")
}

func renderConfigView(view configView) string {
	if len(view.Entries) == 0 {
		return "No config values."
	}

	lines := make([]string, 0, len(view.Entries))
	for _, entry := range view.Entries {
		if entry.IsSet {
			lines = append(lines, fmt.Sprintf("%s: %v", entry.Key, entry.Value))
			continue
		}
		lines = append(lines, entry.Key+": (unset)")
	}
	return strings.Join(lines, "\n")
}

func formatLoginTimeout(timeoutSeconds int) string {
	duration := time.Duration(timeoutSeconds) * time.Second
	hours := int(duration / time.Hour)
	duration -= time.Duration(hours) * time.Hour
	minutes := int(duration / time.Minute)
	duration -= time.Duration(minutes) * time.Minute
	seconds := int(duration / time.Second)

	if hours > 0 {
		return fmt.Sprintf("%dh %02dm %02ds", hours, minutes, seconds)
	}
	if minutes > 0 {
		return fmt.Sprintf("%dm %02ds", minutes, seconds)
	}
	return fmt.Sprintf("%ds", seconds)
}

func stringPtrValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func valueOrDefault(value *string, fallback string) string {
	if value == nil || *value == "" {
		return fallback
	}
	return *value
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
