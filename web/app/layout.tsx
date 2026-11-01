import type { ReactNode } from "react";
import "./globals.css";
export const metadata={title:"MediConnect",description:"Telemedicine and semantic historical case matching platform"};
export default function RootLayout({children}:{children:ReactNode}){return <html lang="en"><body>{children}</body></html>}
