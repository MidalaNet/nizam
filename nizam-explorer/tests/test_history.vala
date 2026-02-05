using GLib;

int main (string[] args) {
    var h = new ExplorerHistory();
    assert(!h.can_back());
    assert(!h.can_forward());

    var f1 = File.new_for_path("/tmp");
    h.push_back(f1);
    assert(h.can_back());
    assert(h.pop_back().equal(f1));
    assert(!h.can_back());

    var f2 = File.new_for_path("/usr");
    h.push_forward(f2);
    assert(h.can_forward());
    assert(h.pop_forward().equal(f2));
    assert(!h.can_forward());

    stdout.printf("1..1\n");
    stdout.printf("ok 1 - history\n");
    return 0;
}
