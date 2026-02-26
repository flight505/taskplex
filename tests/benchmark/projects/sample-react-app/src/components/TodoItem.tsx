// GAP: S019 — no loading state during mutations

interface Todo {
  id: string;
  title: string;
  completed: boolean;
}

interface TodoItemProps {
  todo: Todo;
  onToggle: (id: string) => void;
  onDelete: (id: string) => void;
}

export function TodoItem({ todo, onToggle, onDelete }: TodoItemProps) {
  return (
    <li
      style={{
        display: "flex",
        alignItems: "center",
        gap: "8px",
        padding: "8px 0",
        borderBottom: "1px solid #eee",
      }}
    >
      <input
        type="checkbox"
        checked={todo.completed}
        onChange={() => onToggle(todo.id)}
        aria-label={`Mark "${todo.title}" as ${todo.completed ? "incomplete" : "complete"}`}
      />
      <span
        style={{
          flex: 1,
          textDecoration: todo.completed ? "line-through" : "none",
          color: todo.completed ? "#999" : "#333",
        }}
      >
        {todo.title}
      </span>
      {/* GAP: S013 — inline button styling */}
      <button
        onClick={() => onDelete(todo.id)}
        style={{
          padding: "4px 8px",
          backgroundColor: "#dc3545",
          color: "white",
          border: "none",
          borderRadius: "4px",
          cursor: "pointer",
          fontSize: "12px",
        }}
      >
        Delete
      </button>
    </li>
  );
}
