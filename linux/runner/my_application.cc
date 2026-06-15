#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <gio/gio.h>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Clears the cached window pointer once GTK destroys the native window.
static void on_window_destroy(GtkWidget* widget, gpointer user_data) {
  (void)widget;
  MyApplication* self = MY_APPLICATION(user_data);
  self->window = nullptr;
}

// Handles desktop chrome commands from Flutter.
static void handle_window_method_call(MyApplication* self,
                                      FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (self->window == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_iconify(self->window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    const gboolean maximized = gtk_window_is_maximized(self->window);
    if (maximized) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(!maximized)));
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(gtk_window_is_maximized(self->window))));
  } else if (g_strcmp0(method, "close") == 0) {
    gtk_window_close(self->window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "hideToTray") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "startDrag") == 0) {
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
    if (display != nullptr) {
      GdkSeat* seat = gdk_display_get_default_seat(display);
      GdkDevice* pointer =
          seat == nullptr ? nullptr : gdk_seat_get_pointer(seat);
      if (pointer != nullptr) {
        gint root_x = 0;
        gint root_y = 0;
        gdk_device_get_position(pointer, nullptr, &root_x, &root_y);
        gtk_window_begin_move_drag(self->window, 1, root_x, root_y,
                                   GDK_CURRENT_TIME);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  handle_window_method_call(self, method_call);
}

static void register_window_channel(MyApplication* self, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      messenger, "remote_storage/window_controls", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            method_call_cb, self, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void apply_window_icon(GtkWindow* window) {
  const gchar* resource_root = g_getenv("FLUTTER_ASSETS_DIR");
  g_autofree gchar* icon_path = nullptr;

  if (resource_root != nullptr && resource_root[0] != '\0') {
    icon_path = g_build_filename(resource_root, "..", "app_icon.png", nullptr);
  } else {
    icon_path = g_build_filename(g_get_current_dir(), "data", "app_icon.png", nullptr);
  }

  if (icon_path == nullptr) {
    return;
  }

  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_file(icon_path, &error);
  if (pixbuf != nullptr) {
    gtk_window_set_icon(window, pixbuf);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  // Linux uses app-owned chrome, so hide the system decorations entirely.
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "云卷");
  apply_window_icon(window);

  gint default_width = 980;
  gint default_height = 640;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (display != nullptr) {
    GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
    if (monitor != nullptr) {
      GdkRectangle geometry = {};
      gdk_monitor_get_geometry(monitor, &geometry);
      default_width = CLAMP((geometry.width * 72) / 100, 860, 1080);
      default_height = CLAMP((geometry.height * 66) / 100, 560, 640);
    }
  }
  gtk_window_set_default_size(window, default_width, default_height);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(
      [](FlPluginRegistry* registry) {
        // Multi-window previews create a fresh Flutter engine, so register all
        // generated plugins before the child window configures its chrome.
        fl_register_plugins(registry);
      });
  register_window_channel(self, view);
  g_signal_connect(window, "destroy", G_CALLBACK(on_window_destroy), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->window_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("云卷");

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
