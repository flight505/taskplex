// GAP: S013 — inline button styling, should use shared Button component

import { useState } from "react";

export function SettingsPage() {
  const [saved, setSaved] = useState(false);

  const handleSave = () => {
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <div>
      <h1>Settings</h1>
      <p>Configure your preferences here.</p>
      {saved && <p style={{ color: "green" }}>Settings saved!</p>}
      {/* GAP: inline button, duplicate styling from LoginPage */}
      <button
        onClick={handleSave}
        style={{
          padding: "8px 16px",
          backgroundColor: "#0066cc",
          color: "white",
          border: "none",
          borderRadius: "4px",
          cursor: "pointer",
        }}
      >
        Save Settings
      </button>
      <button
        onClick={() => window.location.reload()}
        style={{
          padding: "8px 16px",
          backgroundColor: "#dc3545",
          color: "white",
          border: "none",
          borderRadius: "4px",
          cursor: "pointer",
          marginLeft: "8px",
        }}
      >
        Reset
      </button>
    </div>
  );
}
