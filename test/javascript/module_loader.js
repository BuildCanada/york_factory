const testDirectory = new URL("./", import.meta.url)
const applicationDirectory = new URL("../../app/javascript/", import.meta.url)

export async function resolve(specifier, context, nextResolve) {
  if (specifier === "@hotwired/stimulus") {
    return nextResolve(new URL("node_modules/@hotwired/stimulus/dist/stimulus.js", testDirectory).href, context)
  }

  if (specifier.startsWith("controllers/")) {
    specifier = new URL(`${specifier}.js`, applicationDirectory).href
  }

  const resolution = await nextResolve(specifier, context)
  return resolution.url.startsWith(applicationDirectory.href) ? { ...resolution, format: "module" } : resolution
}
