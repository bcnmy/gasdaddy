// Skip an individual test
function test_SomeFunction() public {
    if (vm.envOr("SKIP_TEST", false)) {
        return;
    }
    // Test code here
}

// Skip an entire contract
contract SkippedTestContract is Test {
    function setUp() public {}

    function test_Function1() public skip {}
    function test_Function2() public skip {}
}
