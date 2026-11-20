public class BranchDemo {
    record Pair(int left, int right) {}

    static int choose(int value) {
        return switch (value) {
            case 0 -> 11;
            case 1, 2 -> 22;
            default -> -1;
        };
    }

    public static void main(String[] args) {
        Pair pair = new Pair(2, 3);
        System.out.println(choose(pair.left()) + pair.right());
    }
}
