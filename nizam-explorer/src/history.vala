using GLib;

public class ExplorerHistory : Object {
    private File[] back_stack = {};
    private File[] forward_stack = {};

    public bool can_back () {
        return back_stack.length > 0;
    }

    public bool can_forward () {
        return forward_stack.length > 0;
    }

    public void clear_forward () {
        forward_stack = {};
    }

    public void push_back (File dir) {
        back_stack += dir;
    }

    public void push_forward (File dir) {
        forward_stack += dir;
    }

    public File? pop_back () {
        if (back_stack.length == 0) return null;
        var dir = back_stack[back_stack.length - 1];
        back_stack = back_stack[0:back_stack.length - 1];
        return dir;
    }

    public File? pop_forward () {
        if (forward_stack.length == 0) return null;
        var dir = forward_stack[forward_stack.length - 1];
        forward_stack = forward_stack[0:forward_stack.length - 1];
        return dir;
    }
}
