package cli

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"cookey/internal/config"
	"cookey/internal/models"
)

func runSessionExport(args []string) error {
	fs := flag.NewFlagSet("session-export", flag.ContinueOnError)
	out := fs.String("out", "", "")
	pretty := fs.Bool("pretty", false, "")
	latest := fs.Bool("latest", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args, "out")
	if err != nil {
		return err
	}
	if *help {
		printSessionExportUsage()
		return nil
	}
	if len(positionals) > 1 {
		return cliError{message: sessionExportUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rid := ""
	if len(positionals) == 1 {
		rid = positionals[0]
	}
	if rid != "" && *latest {
		return cliError{message: "use either [rid] or --latest, not both"}
	}
	if rid == "" {
		rid, err = config.LatestSessionRID(context.Paths)
		if err != nil {
			return err
		}
		if rid == "" {
			return cliError{message: "no local sessions found"}
		}
	}

	sessionPath := context.Paths.SessionPath(rid)
	if _, err := os.Stat(sessionPath); err != nil {
		descriptorPath := context.Paths.DaemonPath(rid)
		if descriptor, descriptorErr := config.ReadJSON[models.DaemonDescriptor](descriptorPath); descriptorErr == nil {
			message := fmt.Sprintf("session not found for rid: %s (status: %s", rid, descriptor.Status)
			if descriptor.ErrorMessage != nil && *descriptor.ErrorMessage != "" {
				message += ", error: " + *descriptor.ErrorMessage
			}
			message += ")"
			return cliError{message: message}
		}
		return cliError{message: "session not found for rid: " + rid}
	}

	session, err := config.ReadJSON[models.SessionFile](sessionPath)
	if err != nil {
		return err
	}

	storageState := models.PlaywrightStorageState{
		Cookies: session.Cookies,
		Origins: session.Origins,
	}
	data, err := encodeJSON(storageState, *pretty)
	if err != nil {
		return err
	}

	if *out != "" {
		target := *out
		if !filepath.IsAbs(target) {
			cwd, err := os.Getwd()
			if err != nil {
				return err
			}
			target = filepath.Join(cwd, target)
		}
		return os.WriteFile(target, data, 0o644)
	}

	if _, err := os.Stdout.Write(data); err != nil {
		return err
	}
	if len(data) == 0 || data[len(data)-1] != '\n' {
		_, _ = os.Stdout.Write([]byte{'\n'})
	}
	return nil
}

func runSessionList(args []string) error {
	fs := flag.NewFlagSet("session-list", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printSessionListUsage()
		return nil
	}
	if len(positionals) != 0 {
		return cliError{message: sessionListUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rids, err := config.ListLocalRIDs(context.Paths)
	if err != nil {
		return err
	}

	snapshots := make([]models.StatusSnapshot, 0, len(rids))
	for _, rid := range rids {
		snapshots = append(snapshots, config.StatusSnapshot(rid, context))
	}
	return emit(snapshots, *jsonOutput)
}

func runSessionDelete(args []string) error {
	fs := flag.NewFlagSet("session-delete", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printSessionDeleteUsage()
		return nil
	}
	if len(positionals) != 1 {
		return cliError{message: sessionDeleteUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rid := positionals[0]
	sessionDeleted, daemonDeleted, err := config.DeleteLocalRID(context.Paths, rid)
	if err != nil {
		switch {
		case errors.Is(err, os.ErrNotExist):
			return cliError{message: "no local request found for rid: " + rid}
		case errors.Is(err, config.ErrActiveRequest):
			return cliError{message: "request is still active and cannot be deleted: " + rid}
		default:
			return err
		}
	}

	return emit(models.DeleteOutput{
		RID:            rid,
		SessionDeleted: sessionDeleted,
		DaemonDeleted:  daemonDeleted,
	}, *jsonOutput)
}

func runSessionClean(args []string) error {
	fs := flag.NewFlagSet("session-clean", flag.ContinueOnError)
	jsonOutput := fs.Bool("json", false, "")
	help := fs.Bool("help", false, "")

	positionals, err := parseInterspersedFlags(fs, args)
	if err != nil {
		return err
	}
	if *help {
		printSessionCleanUsage()
		return nil
	}
	if len(positionals) != 0 {
		return cliError{message: sessionCleanUsage()}
	}

	context, err := config.Bootstrap()
	if err != nil {
		return err
	}

	rids, err := config.ListLocalRIDs(context.Paths)
	if err != nil {
		return err
	}

	deleted := make([]models.DeleteOutput, 0, len(rids))
	skipped := make([]models.StatusSnapshot, 0)
	for _, rid := range rids {
		sessionDeleted, daemonDeleted, err := config.DeleteLocalRID(context.Paths, rid)
		if err != nil {
			if errors.Is(err, config.ErrActiveRequest) {
				skipped = append(skipped, config.StatusSnapshot(rid, context))
				continue
			}
			return err
		}

		deleted = append(deleted, models.DeleteOutput{
			RID:            rid,
			SessionDeleted: sessionDeleted,
			DaemonDeleted:  daemonDeleted,
		})
	}

	return emit(models.CleanOutput{Deleted: deleted, Skipped: skipped}, *jsonOutput)
}
