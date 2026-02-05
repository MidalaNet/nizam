[CCode (cheader_filename = "x11_rootpixmap.h")]
namespace NizamX11 {
  [CCode (cname = "nizam_x11_get_root_background")]
  public Gdk.Pixbuf? get_root_background();

  [CCode (cname = "nizam_gdk_is_x11")]
  public bool is_x11();
}
