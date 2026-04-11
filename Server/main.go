package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"
)

func main() {
	config := parseConfig(os.Args[1:])

	log.Println("Cookey Relay Server starting...")
	log.Printf("   Host: %s", config.Host)
	log.Printf("   Port: %d", config.Port)
	log.Printf("   Public URL: %s", config.PublicURL)
	log.Printf("   Default TTL: %ds", int(config.DefaultTTL.Seconds()))
	log.Printf("   Max Payload: %dKB", config.MaxPayloadSize/1024)
	if config.DisablePushRateLimit {
		log.Println("   Push Rate Limit: disabled")
	} else {
		log.Println("   Push Rate Limit: enabled")
	}
	if config.APNSConfiguration != nil {
		log.Println("   APNs: enabled")
	} else {
		log.Println("   APNs: disabled")
	}
	if config.FCMConfiguration != nil {
		log.Println("   FCM: enabled")
	} else {
		log.Println("   FCM: disabled")
	}

	storage := NewStorage(config.MaxPayloadSize)
	apnBlocker := NewAPNTokenBlocker()
	var pushLimiter *APNPushRateLimiter
	if !config.DisablePushRateLimit {
		pushLimiter = NewAPNPushRateLimiter()
	}

	var apnsClient notificationSender
	if config.APNSConfiguration != nil {
		apnsClient = NewAPNSClient(*config.APNSConfiguration)
	}

	var fcmClient *FCMClient
	if config.FCMConfiguration != nil {
		fcmClient = NewFCMClient(*config.FCMConfiguration)
	}

	routes := &Routes{
		storage:     storage,
		config:      config,
		apnsClient:  apnsClient,
		fcmClient:   fcmClient,
		apnBlocker:  apnBlocker,
		pushLimiter: pushLimiter,
	}

	mux := http.NewServeMux()
	routes.Register(mux)

	// Wrap with Server header middleware
	handler := serverHeaderMiddleware(mux)

	// Start cleanup goroutine
	go runCleanup(storage, apnBlocker, pushLimiter, 30*time.Second)

	addr := fmt.Sprintf("%s:%d", config.Host, config.Port)
	server := &http.Server{
		Addr:         addr,
		Handler:      handler,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}
	log.Println("Server ready")
	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

// serverHeaderMiddleware adds the Server header to every response.
func serverHeaderMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Server", "Cookey-Relay/1.0")
		next.ServeHTTP(w, r)
	})
}

// runCleanup periodically removes expired requests.
func runCleanup(storage *Storage, blocker *APNTokenBlocker, limiter *APNPushRateLimiter, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for range ticker.C {
		expired := storage.CleanupExpired()
		if blocker != nil {
			blocker.Cleanup()
		}
		if limiter != nil {
			limiter.Cleanup()
		}
		if len(expired) > 0 {
			log.Printf("Cleaned up %d expired requests", len(expired))
		}
	}
}

// parseConfig parses CLI args then overlays environment variables.
func parseConfig(args []string) ServerConfig {
	config := ServerConfig{
		Host:           "0.0.0.0",
		Port:           8080,
		DefaultTTL:     5 * time.Minute,
		MaxPayloadSize: 1 * 1024 * 1024, // 1MB
	}

	// Parse CLI args
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--host", "-h":
			if i+1 < len(args) {
				config.Host = args[i+1]
				i++
			}
		case "--port", "-p":
			if i+1 < len(args) {
				if p, err := strconv.Atoi(args[i+1]); err == nil {
					config.Port = p
				}
				i++
			}
		case "--public-url", "-u":
			if i+1 < len(args) {
				config.PublicURL = args[i+1]
				i++
			}
		case "--ttl", "-t":
			if i+1 < len(args) {
				if t, err := strconv.ParseFloat(args[i+1], 64); err == nil {
					config.DefaultTTL = time.Duration(t * float64(time.Second))
				}
				i++
			}
		case "--max-payload", "-m":
			if i+1 < len(args) {
				if m, err := strconv.Atoi(args[i+1]); err == nil {
					config.MaxPayloadSize = m
				}
				i++
			}
		case "--help":
			printHelp()
			os.Exit(0)
		}
	}

	// Environment variables override CLI args (matching main.swift:72-76)
	if v := os.Getenv("COOKEY_HOST"); v != "" {
		config.Host = v
	}
	if v := os.Getenv("COOKEY_PORT"); v != "" {
		if p, err := strconv.Atoi(v); err == nil {
			config.Port = p
		}
	}
	if v := os.Getenv("COOKEY_PUBLIC_URL"); v != "" {
		config.PublicURL = v
	}
	if v := os.Getenv("COOKEY_DISABLE_PUSH_RATE_LIMIT"); v != "" {
		if disabled, err := strconv.ParseBool(v); err == nil {
			config.DisablePushRateLimit = disabled
		}
	}

	// Default public URL if not set
	if config.PublicURL == "" {
		config.PublicURL = fmt.Sprintf("http://%s:%d", config.Host, config.Port)
	}

	// Load APNs configuration from environment
	config.APNSConfiguration = loadAPNSConfiguration()

	// Load FCM configuration from environment
	config.FCMConfiguration = loadFCMConfiguration()

	return config
}

func loadAPNSConfiguration() *APNSConfiguration {
	teamID := os.Getenv("COOKEY_APNS_TEAM_ID")
	keyID := os.Getenv("COOKEY_APNS_KEY_ID")
	bundleID := os.Getenv("COOKEY_APNS_BUNDLE_ID")
	privateKeyPath := os.Getenv("COOKEY_APNS_PRIVATE_KEY_PATH")

	if teamID == "" || keyID == "" || bundleID == "" || privateKeyPath == "" {
		return nil
	}

	return &APNSConfiguration{
		TeamID:         teamID,
		KeyID:          keyID,
		BundleID:       bundleID,
		PrivateKeyPath: privateKeyPath,
	}
}

func loadFCMConfiguration() *FCMConfiguration {
	serviceAccountPath := os.Getenv("COOKEY_FCM_SERVICE_ACCOUNT_PATH")
	projectID := os.Getenv("COOKEY_FCM_PROJECT_ID")

	if serviceAccountPath == "" {
		return nil
	}

	// If project ID not set, try to read from service account file
	if projectID == "" {
		data, err := os.ReadFile(serviceAccountPath)
		if err == nil {
			var sa serviceAccountKey
			if json.Unmarshal(data, &sa) == nil && sa.ProjectID != "" {
				projectID = sa.ProjectID
			}
		}
	}

	if projectID == "" {
		return nil
	}

	return &FCMConfiguration{
		ServiceAccountKeyPath: serviceAccountPath,
		ProjectID:             projectID,
	}
}

func printHelp() {
	fmt.Println(`Cookey Relay Server

Usage: server [OPTIONS]

Options:
  -h, --host <host>         Bind host (default: 0.0.0.0)
  -p, --port <port>         Bind port (default: 8080)
  -u, --public-url <url>    Public URL for QR codes
  -t, --ttl <seconds>       Default request TTL (default: 300)
  -m, --max-payload <bytes> Max payload size (default: 1048576)
  --help                    Show this help message

Environment Variables:
  COOKEY_HOST             Bind host
  COOKEY_PORT             Bind port
  COOKEY_PUBLIC_URL       Public URL
  COOKEY_DISABLE_PUSH_RATE_LIMIT Disable APNs/FCM push rate limiting for testing
  COOKEY_APNS_TEAM_ID     Apple Developer team ID
  COOKEY_APNS_KEY_ID      APNs key ID
  COOKEY_APNS_BUNDLE_ID   App bundle identifier
  COOKEY_APNS_PRIVATE_KEY_PATH Path to APNs .p8 key
  COOKEY_FCM_SERVICE_ACCOUNT_PATH Path to Firebase service account JSON
  COOKEY_FCM_PROJECT_ID        Firebase project ID (auto-detected from SA file)

Examples:
  server
  server --port 3000
  server --host 127.0.0.1 --port 8080`)
}
