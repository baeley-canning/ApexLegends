public class Probe {
    public static void main(String[] args) {
        for (int value : new int[]{-1, 0, 1, 2, 9}) {
            System.out.println(value + ":" + BranchDemo.choose(value));
        }
    }
}
