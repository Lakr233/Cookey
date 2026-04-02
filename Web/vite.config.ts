import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        "get-started": resolve(__dirname, "get-started.html"),
        "test-login-instruction": resolve(
          __dirname,
          "test-login-instruction.html",
        ),
        "test-login-site": resolve(__dirname, "test-login-site.html"),
      },
    },
  },
});
