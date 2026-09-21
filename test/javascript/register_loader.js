import { register } from "node:module"

register("./module_loader.js", import.meta.url)
