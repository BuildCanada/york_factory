import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Senior Benefit Simulator | Build Canada",
  description: "Explore how OAS, GIS, and tax policy affect Canadian seniors. Compare current rules vs reforms.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col font-sans">{children}</body>
    </html>
  );
}
