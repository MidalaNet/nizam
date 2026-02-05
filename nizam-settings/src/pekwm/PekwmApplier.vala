using GLib;

namespace NizamSettings {
    public class PekwmApplier : Object {
        private static bool run_cmd (string[] argv, out string stderr_out) {
            stderr_out = "";
            try {
                string? out_text = null;
                string? err_text = null;
                int status = 0;
                Process.spawn_sync(
                    null,
                    argv,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    out out_text,
                    out err_text,
                    out status
                );
                if (err_text != null) stderr_out = err_text.strip();
                return status == 0;
            } catch (Error e) {
                stderr_out = e.message;
                return false;
            }
        }

        private static string? find_pekwm_ctrl () {
            var p = Environment.find_program_in_path("pekwm_ctrl");
            if (p != null && p.strip().length > 0) return p;
            return null;
        }

        public bool try_reload (out string stderr_out) {
            stderr_out = "";
            var ctrl = find_pekwm_ctrl();
            if (ctrl == null) {
                stderr_out = "pekwm_ctrl not found in PATH";
                return false;
            }
            var argv = new string[] { ctrl, "reload" };
            return run_cmd(argv, out stderr_out);
        }

        public bool try_restart (out string stderr_out) {
            stderr_out = "";
            var ctrl = find_pekwm_ctrl();
            if (ctrl != null) {
                var argv = new string[] { ctrl, "restart" };
                return run_cmd(argv, out stderr_out);
            }

            
            var pkill = Environment.find_program_in_path("pkill");
            if (pkill != null && pkill.strip().length > 0) {
                
                var argv2 = new string[] { pkill, "-HUP", "-x", "pekwm" };
                if (run_cmd(argv2, out stderr_out)) return true;

                var argv3 = new string[] { pkill, "-HUP", "-f", "pekwm" };
                return run_cmd(argv3, out stderr_out);
            }

            stderr_out = "pekwm_ctrl not found in PATH and pkill not found";
            return false;
        }
    }
}
