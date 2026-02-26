// GAP: S013 — inline button styling, should use shared Button component

export function DashboardPage() {
  return (
    <div>
      <h1>Dashboard</h1>
      <p>Welcome to your dashboard.</p>
      {/* GAP: inline button, yet another copy of styling */}
      <button
        style={{
          padding: "8px 16px",
          backgroundColor: "#28a745",
          color: "white",
          border: "none",
          borderRadius: "4px",
          cursor: "pointer",
        }}
      >
        Create New
      </button>
    </div>
  );
}
