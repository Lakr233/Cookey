import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import TestLoginInstructionPage from "./pages/TestLoginInstructionPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <TestLoginInstructionPage />
  </StrictMode>,
);
