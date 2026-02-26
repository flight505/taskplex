// BUG: S011 — race condition. No request cancellation, stale responses can override fresh ones.

import { useState, useEffect } from "react";

interface SearchResult {
  id: string;
  title: string;
}

interface SearchBarProps {
  onResults: (results: SearchResult[]) => void;
  apiUrl: string;
}

export function SearchBar({ onResults, apiUrl }: SearchBarProps) {
  const [query, setQuery] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (!query.trim()) {
      onResults([]);
      return;
    }

    // BUG: no AbortController, no cancellation of stale requests
    const timer = setTimeout(async () => {
      setIsLoading(true);
      try {
        const response = await fetch(`${apiUrl}/search?q=${encodeURIComponent(query)}`);
        const data = await response.json();
        // BUG: this may set results from a stale request
        onResults(data.results);
      } catch {
        // ignore
      } finally {
        setIsLoading(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [query, apiUrl, onResults]);

  return (
    <div>
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Search..."
        aria-label="Search"
      />
      {isLoading && <span aria-busy="true">Loading...</span>}
    </div>
  );
}
