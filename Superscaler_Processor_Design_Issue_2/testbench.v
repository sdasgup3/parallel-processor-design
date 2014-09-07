
// ============================================================================
// TESTBENCH FOR SUPERSCALAR CPU CORE
// ============================================================================

module tb ();
reg clk;


superscalar_cpu cpu (
	clk
);

initial begin
	clk = 1;
	#13000 clk = 0;
	$stop;
end

always clk = #1 ~clk;

endmodule
