// GAP: S015 — no ErrorBoundary wrapping routes, no global theme support

import { NavBar } from "./components/NavBar";
import { LoginPage } from "./pages/LoginPage";
import { DashboardPage } from "./pages/DashboardPage";
import { SettingsPage } from "./pages/SettingsPage";
import { TodoPage } from "./pages/TodoPage";

// GAP: no routing — just renders all pages stacked (placeholder for story work)
export function App() {
  const handleLogin = async (email: string, _password: string) => {
    console.log("Login attempt:", email);
  };

  return (
    <div>
      <NavBar />
      <main>
        <LoginPage onLogin={handleLogin} />
        <DashboardPage />
        <TodoPage />
        <SettingsPage />
      </main>
    </div>
  );
}
