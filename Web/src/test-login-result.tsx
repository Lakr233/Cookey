import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import TestLoginResultPage from "./pages/TestLoginResultPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <TestLoginResultPage />
  </StrictMode>,
);