import type { ReactNode } from "react";

export const metadata = {
  title: "MediConnect API",
  description: "MediConnect backend API scaffold",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
