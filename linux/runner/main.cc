#include <glib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // Wayland 下 GTK3 默认用 CPU（cairo）绘制窗口，Flutter 每帧画面都要从显存读回，
  // 高分屏上一帧要几十毫秒。让 GDK 用 OpenGL 绘制窗口可以省掉这次读回。
  // 设置 YUNYIN_GDK_GL=0 可关闭（个别驱动若出现显示问题）。
  const gchar* session = g_getenv("XDG_SESSION_TYPE");
  const gchar* backend = g_getenv("GDK_BACKEND");
  gboolean wayland = g_getenv("WAYLAND_DISPLAY") != nullptr || g_strcmp0(session, "wayland") == 0;
  if (wayland && g_strcmp0(backend, "x11") != 0 && g_strcmp0(g_getenv("YUNYIN_GDK_GL"), "0") != 0) {
    g_setenv("GDK_GL", "always", FALSE);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
