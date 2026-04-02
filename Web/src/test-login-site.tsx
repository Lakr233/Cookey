import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import TestLoginSitePage from "./pages/TestLoginSitePage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <TestLoginSitePage />
  </StrictMode>,
);
