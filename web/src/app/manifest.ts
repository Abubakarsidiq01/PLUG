import type { MetadataRoute } from "next";

// Icons come from design/generate-brand.mjs; colours are the paper and ink tokens.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "PLUG",
    short_name: "PLUG",
    description: "Ask for a service. Ask about a place.",
    start_url: "/",
    display: "browser",
    background_color: "#F4F1E8",
    theme_color: "#F4F1E8",
    icons: [
      { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
  };
}
