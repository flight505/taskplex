// GAP: S015 — basic error boundary, no error reporting, no recovery options

import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

// GAP: S015 — no error reporting service integration
// GAP: S015 — no "retry" or "go back" actions
export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: "20px", textAlign: "center" }}>
          <h2>Something went wrong</h2>
          <p style={{ color: "#666" }}>
            {this.state.error?.message ?? "Unknown error"}
          </p>
          {/* GAP: no recovery actions — just shows the error */}
        </div>
      );
    }

    return this.props.children;
  }
}
