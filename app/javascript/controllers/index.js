import { application } from "controllers/application"

import TabsController from "controllers/tabs_controller"
application.register("tabs", TabsController)

import SortableController from "controllers/sortable_controller"
application.register("sortable", SortableController)

import SidebarController from "controllers/sidebar_controller"
application.register("sidebar", SidebarController)
