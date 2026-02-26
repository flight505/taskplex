// BUG: S004 — uses string className instead of CSS module

import { useState } from "react";
import styles from "./NavBar.module.css";

interface NavItem {
  label: string;
  path: string;
}

const NAV_ITEMS: NavItem[] = [
  { label: "Home", path: "/" },
  { label: "Todos", path: "/todos" },
  { label: "Settings", path: "/settings" },
];

export function NavBar() {
  const [activePath, setActivePath] = useState("/");

  return (
    <nav className={styles.nav}>
      <ul className={styles.navList}>
        {NAV_ITEMS.map((item) => (
          <li key={item.path}>
            <a
              href={item.path}
              // BUG: should be styles.navActive, not string 'nav-active'
              className={activePath === item.path ? "nav-active" : styles.navLink}
              onClick={(e) => {
                e.preventDefault();
                setActivePath(item.path);
              }}
            >
              {item.label}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
