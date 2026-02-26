// GAP: S019 — naive implementation, no optimistic updates, no error handling
// This hook is the target for the T3 "optimistic mutations" story

import { useState, useEffect, useCallback } from "react";

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

const API_URL = "/api/todos";

export function useTodos() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch(API_URL)
      .then((res) => {
        if (!res.ok) throw new Error("Failed to fetch todos");
        return res.json();
      })
      .then(setTodos)
      .catch((err) => setError(err.message))
      .finally(() => setIsLoading(false));
  }, []);

  // GAP: no optimistic update — waits for server
  const addTodo = useCallback(async (title: string) => {
    const res = await fetch(API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title }),
    });
    if (!res.ok) throw new Error("Failed to add todo");
    const created = await res.json();
    setTodos((prev) => [...prev, created]);
    return created;
  }, []);

  // GAP: no optimistic update — waits for server
  const toggleTodo = useCallback(
    async (id: string) => {
      const todo = todos.find((t) => t.id === id);
      if (!todo) return;
      const res = await fetch(`${API_URL}/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ completed: !todo.completed }),
      });
      if (!res.ok) throw new Error("Failed to toggle todo");
      const updated = await res.json();
      setTodos((prev) => prev.map((t) => (t.id === id ? updated : t)));
    },
    [todos],
  );

  // GAP: no optimistic update — waits for server
  const deleteTodo = useCallback(async (id: string) => {
    const res = await fetch(`${API_URL}/${id}`, { method: "DELETE" });
    if (!res.ok) throw new Error("Failed to delete todo");
    setTodos((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return { todos, isLoading, error, addTodo, toggleTodo, deleteTodo };
}
