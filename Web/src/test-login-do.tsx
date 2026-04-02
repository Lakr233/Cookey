import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import TestLoginDoPage from "./pages/TestLoginDoPage";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <TestLoginDoPage />
  </StrictMode>,
);
