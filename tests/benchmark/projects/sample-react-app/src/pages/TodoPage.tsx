// GAP: S019 — no optimistic updates, mutations block UI until server responds

import { useState, useEffect } from "react";
import { TodoItem } from "../components/TodoItem";

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

export function TodoPage() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [newTitle, setNewTitle] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  // GAP: S019 — fetch is not abstracted, no error handling
  useEffect(() => {
    fetch("/api/todos")
      .then((res) => res.json())
      .then((data) => {
        setTodos(data);
        setIsLoading(false);
      });
  }, []);

  // GAP: S019 — blocks on server response, no optimistic update
  const addTodo = async () => {
    if (!newTitle.trim()) return;
    const res = await fetch("/api/todos", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: newTitle }),
    });
    const created = await res.json();
    setTodos((prev) => [...prev, created]);
    setNewTitle("");
  };

  // GAP: S019 — blocks on server response, no optimistic toggle
  const toggleTodo = async (id: string) => {
    const todo = todos.find((t) => t.id === id);
    if (!todo) return;
    const res = await fetch(`/api/todos/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ completed: !todo.completed }),
    });
    const updated = await res.json();
    setTodos((prev) => prev.map((t) => (t.id === id ? updated : t)));
  };

  // GAP: S019 — blocks on server response, no optimistic delete
  const deleteTodo = async (id: string) => {
    await fetch(`/api/todos/${id}`, { method: "DELETE" });
    setTodos((prev) => prev.filter((t) => t.id !== id));
  };

  if (isLoading) return <p>Loading todos...</p>;

  return (
    <div>
      <h1>Todo List</h1>
      <div>
        <input
          type="text"
          value={newTitle}
          onChange={(e) => setNewTitle(e.target.value)}
          placeholder="What needs to be done?"
          aria-label="New todo"
        />
        {/* GAP: S013 — inline button styling, same as other pages */}
        <button
          onClick={addTodo}
          style={{
            padding: "8px 16px",
            backgroundColor: "#0066cc",
            color: "white",
            border: "none",
            borderRadius: "4px",
            cursor: "pointer",
            marginLeft: "8px",
          }}
        >
          Add
        </button>
      </div>
      <ul style={{ listStyle: "none", padding: 0 }}>
        {todos.map((todo) => (
          <TodoItem
            key={todo.id}
            todo={todo}
            onToggle={toggleTodo}
            onDelete={deleteTodo}
          />
        ))}
      </ul>
    </div>
  );
}
