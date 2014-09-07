module pipelined_cpu(clk);
  input  clk ; //system clock
    
  /******************* Mnemonic op codes ***************************/
  parameter NOP = 6'd0;
                      /***** Memory reference (load 1-4) ********/
  parameter LW  = 6'd1;  parameter LB  = 6'd2;  parameter LBU = 6'd3;  parameter LH  = 6'd4;  
  
                      /***** Memory reference (store 5-7) ********/
  parameter SW  = 6'd5;   parameter SB  = 6'd6; parameter SH  = 6'd7;  /*Srore Half Word*/
  
                      /***** Register-Register operations(8-21) ********/
  parameter ADD  = 6'd8;  parameter SUB  = 6'd9;  parameter MULT = 6'd10;  parameter DIV  = 6'd11;  
  parameter AND  = 6'd12;  parameter OR   = 6'd13; parameter XOR  = 6'd14;  parameter SLT  = 6'd15;  
  parameter SGT  = 6'd16;  parameter SLE  = 6'd17;  parameter SGE  = 6'd18;  parameter EQ   = 6'd19;  
  parameter NEQ  = 6'd20;  parameter MV   = 6'd21; 
  
                      /***** Register-Immediate operations(21-35) **********/
  parameter ADDI  = 6'd22;  parameter SUBI  = 6'd23;  parameter MULTI = 6'd24;  parameter DIVI  = 6'd25;  
  parameter ANDI  = 6'd26;  parameter ORI   = 6'd27; parameter XORI  = 6'd28;  parameter SLTI  = 6'd29;  
  parameter SGTI  = 6'd30;  parameter SLEI  = 6'd31;  parameter SGEI  = 6'd32;  parameter EQI   = 6'd33;  
  parameter NEQI  = 6'd34;  parameter MVI   = 6'd35;
  
                      /***** Control operations(35-43) ******************/
  parameter BNEZ  = 6'd36;parameter BEQZ  = 6'd37;parameter J     = 6'd38;parameter JR    = 6'd39;
  parameter CALL  = 6'd40;parameter CALLR = 6'd41; parameter HALT = 6'd42; parameter RET = 6'd43;
  
  
  /******************* Core cpu parameters ***********************
  ** Memory             : Word addressable; Big Endian mode ; 32-bit address; Separate Instruction & Data memory
  ** Register File      : 32 general purpose registers(32-bit)
  ** Instruction Memory : size 1024; 
  ** Instruction Size   : 32 bit;
  ****************************************************************/ 
  parameter INSTRUCTION_MEMORY_SIZE = 10  ; parameter REGISTER_FILE_SIZE  =  5; 
  parameter OPCODE_SIZE             = 6   ; parameter DATA_MEMORY_SIZE    = 10;   
  
  reg [ 0:31  ]     IMEM    [0: 2 ** INSTRUCTION_MEMORY_SIZE  -1 ] ;	   // Instruction Memory
  reg [ 0:31  ]     DMEM    [0: 2 ** DATA_MEMORY_SIZE         -1 ];	    // Data Memory
  reg [ 0:31  ]     REGFILE [0: 2 ** REGISTER_FILE_SIZE       -1 ];	    // General Purpose Registers
  reg [ 0 : INSTRUCTION_MEMORY_SIZE  -1]  PC;			                        // program counter

  reg [ 0:31  ]     IF_ID_IR,  IF_ID_NPC;                                                                            //Pipeline Registers : IF Stage
  reg [ 0:31  ]     ID_EX_IR,  ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_IMM;                                               //Pipeline Registers : ID Stage
  reg [ 0:31  ]     EX_MEM_IR,                     EX_MEM_B,          EX_MEM_ALUOUTPUT, EX_MEM_COND;	                //Pipeline Registers : EX Stage      
  reg [ 0:31  ]     MEM_WB_IR,                                        MEM_WB_ALUOUTPUT,              MEM_WB_LMD;     //Pipeline Registers : MEM Stage
  
  wire [0 : OPCODE_SIZE -1] EX_MEM_OP, MEM_WB_OP, ID_EX_OP, IF_ID_OP;                                                           //Access opcodes
  wire [0:31] Ain, Bin;                                                                                               //The ALU inputs
  wire branchtaken, stall, bypassAfromMEM, bypassAfromALUinWB,bypassBfromMEM, bypassBfromALUinWB, bypassAfromLWinWB, bypassBfromLWinWB;   //Bypass Signals
  wire [0:REGISTER_FILE_SIZE - 1] IF_ID_rs, ID_EX_rs, ID_EX_rt, EX_MEM_rd, MEM_WB_rd;                                          //hold register fields
  wire bypassAfromEX_MEMforbranch,  bypassAfromMEM_WBforbranch;
  
  assign EX_MEM_OP  = EX_MEM_IR[0:OPCODE_SIZE -1]; 
  assign MEM_WB_OP  = MEM_WB_IR[0:OPCODE_SIZE -1]; 
  assign ID_EX_OP   = ID_EX_IR[0:OPCODE_SIZE -1] ; 
  assign IF_ID_OP   = IF_ID_IR[0:OPCODE_SIZE -1] ;
  reg [5:0] i; 
  reg finish;
  
  assign ID_EX_rs = ID_EX_IR[6:10];   
  assign ID_EX_rt = ID_EX_IR[11:15]; 
  assign IF_ID_rs  = IF_ID_IR[6:10];  //For branch instruction only
  assign EX_MEM_rd = EX_MEM_OP >= ADDI & EX_MEM_OP <= MVI ? EX_MEM_IR[11:15] : EX_MEM_IR[16:20];
  assign MEM_WB_rd = MEM_WB_OP >= ADDI & MEM_WB_OP <= MVI ? MEM_WB_IR[11:15] : MEM_WB_IR[16:20];

  // The bypass to input A in ID_EX buffer from the EX_MEM buffer for an ALU operation
  
  assign bypassAfromEX_MEMforbranch = (IF_ID_rs == EX_MEM_rd) & (IF_ID_rs!=0) & (EX_MEM_OP >= ADD & EX_MEM_OP <= MVI) & (IF_ID_OP == BNEZ | IF_ID_OP
                                      ==BEQZ);
  assign bypassAfromMEM_WBforbranch = (IF_ID_rs == MEM_WB_rd) & (IF_ID_rs!=0) & (MEM_WB_OP >= ADD & EX_MEM_OP <= MVI) & (IF_ID_OP == BNEZ | IF_ID_OP
                                      ==BEQZ);
  
  assign bypassAfromMEM = (ID_EX_rs == EX_MEM_rd) & (ID_EX_rs!=0) & (EX_MEM_OP >= ADD & EX_MEM_OP <= MVI) & (ID_EX_OP != MVI);
                          //MVI doesn't make any sense for 'A' frwding*/
  
  // The bypass to input B in ID_EX buffer from the EX_MEM buffer for an ALU operation
  assign bypassBfromMEM = (ID_EX_rt== EX_MEM_rd)&(ID_EX_rt!=0) & (EX_MEM_OP >= ADD & EX_MEM_OP <= MVI) & !(ID_EX_OP >= ADDI & ID_EX_OP <= MVI)
                          & (ID_EX_OP != MV) ;
                          //MVI, MV, or any alu immediate instruction doesn't make any sense for 'B' frwding*/
                          
  // The bypass to input A in ID_EX buffer from the MEM_WB buffer for an ALU operation
  assign bypassAfromALUinWB = (ID_EX_rs == MEM_WB_rd) & (ID_EX_rs!=0) & (MEM_WB_OP >= ADD & MEM_WB_OP <= MVI) & (ID_EX_OP != MVI);
                          //MVI doesn't make any sense for 'A' frwding
                          
  // The bypass to input B in ID_EX buffer from the MEM_WB buffer for an ALU operation
  assign bypassBfromALUinWB = (ID_EX_rt== MEM_WB_rd)&(ID_EX_rt!=0) & (MEM_WB_OP >= ADD & MEM_WB_OP <= MVI) & !(ID_EX_OP >= ADDI & ID_EX_OP <= MVI)
                          & (ID_EX_OP != MV) ;
                          //MVI, MV, or any alu immediate instruction doesn't make any sense for 'B' frwding
                          
  // The bypass to input A in ID_EX buffer from the MEM_WB buffer corresponding to LW operation.
  assign bypassAfromLWinWB =( ID_EX_rs == MEM_WB_IR[11:15]) & (ID_EX_rs!=0) & ((MEM_WB_OP == LW) |(MEM_WB_OP == LB) |
                            (MEM_WB_OP == LBU) | (MEM_WB_OP == LH));
                            
  // The bypass to input A in ID_EX buffer from the MEM_WB buffer corresponding to LW operation.
  assign bypassBfromLWinWB = (ID_EX_rt==MEM_WB_IR[11:15]) & (ID_EX_rt!=0) & (((MEM_WB_OP == LW) |(MEM_WB_OP == LB) |
                            (MEM_WB_OP == LBU) | (MEM_WB_OP == LH)));
                            
  // The A input to the ALU is bypassed from EX_MEM buffer if there is a bypass there,
  // Otherwise from MEM_WB if there is a bypass there, and otherwise comes from the ID_EX register
  assign Ain = bypassAfromMEM? EX_MEM_ALUOUTPUT : bypassAfromALUinWB ? MEM_WB_ALUOUTPUT :  bypassAfromLWinWB ? MEM_WB_LMD : ID_EX_A;
  
  // The B input to the ALU is bypassed from EX_MEM if there is a bypass there,
  // Otherwise from MEM_WB if there is a bypass there, and otherwise comes from the ID_EX register
  assign Bin = bypassBfromMEM? EX_MEM_ALUOUTPUT : bypassBfromALUinWB ? MEM_WB_ALUOUTPUT : bypassBfromLWinWB? MEM_WB_LMD: ID_EX_B;
  
  // The signal for detecting a stall based on the use of a result from LW
  assign stall = (MEM_WB_IR[0:5]==LW) && // source instruction is a load
                ( (((ID_EX_OP==LW)|(ID_EX_OP==SW)) && (ID_EX_rs==MEM_WB_rd)) | // stall for address calc
                  ((ID_EX_OP <= ADD & ID_EX_OP <= NEQ) && ((ID_EX_rs==MEM_WB_rd)|(ID_EX_rt==MEM_WB_rd))) | // ALU use
                  ((ID_EX_OP <= ADDI & ID_EX_OP <= NEQI) && (ID_EX_rs==MEM_WB_rd)) | 
                  ((ID_EX_OP == MV) && (ID_EX_rs==MEM_WB_rd)) ); 
                  
  // Signal for a taken branch: instruction is BEQ and registers are equal bypassAfromMEM bypassAfromALUinWB
  /*assign branchtaken =  ((IF_ID_IR[0:5] == BEQZ) && (REGFILE[IF_ID_IR[6:10]] == 32'd0)) | 
                        ((IF_ID_IR[0:5] == BNEZ) && (REGFILE[IF_ID_IR[6:10]] != 32'd0)) |
                        IF_ID_IR[0:5] == JR | IF_ID_IR[0:5] == J | IF_ID_IR[0:5] == CALL | IF_ID_IR[0:5] == CALLR;*/
  /*Branch decision is taken at the begining of the ID stage and forwarding (if necessary) is to be done from ID_EX, EX_MEM, and MEM_WB buffers
  **Also the instruction forwarding the result should not be SW.
  **
  */                      
  assign branchtaken = ((IF_ID_IR[0:5] == BEQZ) && (bypassAfromEX_MEMforbranch ? EX_MEM_ALUOUTPUT == 32'd0 : bypassAfromMEM_WBforbranch ? 
                        MEM_WB_ALUOUTPUT == 32'd0 :REGFILE[IF_ID_IR[6:10]] == 32'd0)) |
                       ((IF_ID_IR[0:5] == BNEZ) && (bypassAfromEX_MEMforbranch ? EX_MEM_ALUOUTPUT != 32'd0 : bypassAfromMEM_WBforbranch ? 
                        MEM_WB_ALUOUTPUT != 32'd0 :REGFILE[IF_ID_IR[6:10]] != 32'd0)) | 
                       IF_ID_IR[0:5] == JR | IF_ID_IR[0:5] == J | IF_ID_IR[0:5] == CALL | IF_ID_IR[0:5] == CALLR; 
  
  
  /************** The initial cpu state bootstrap **************************/
  initial begin 
    PC = 0;
    finish =0;
    $readmemh("bincode.rom",IMEM);
    IF_ID_IR = 32'b0; ID_EX_IR = 32'b0; EX_MEM_IR=32'b0; MEM_WB_IR = 32'b0; 
    
   
    
    IMEM[22] = {BEQZ, 5'd21,21'd38};
    IMEM[23] = {EQ, 5'd2,5'd7,5'd21,11'd0};
    
    /*** Test Program Branch  ************************************
    IMEM[0] = { MVI , 5'd0, 5'd1, 16'd10 };                   //R1 <- 10 ;  
    IMEM[1] = { MVI , 5'd0, 5'd2,  16'd501 };                 //R2<-500
    IMEM[2] = { MVI , 5'd0, 5'd3,  16'd0 };                   //R3<-0
    IMEM[3] = { MV , 5'd1, 5'd0,  5'd4,11'd0  };              //R4<-R1
    IMEM[4] = { ADDI , 5'd3, 5'd3, 16'd100 };                 //R3 <- R3+100 ;  
    IMEM[5] = { SUBI , 5'd4, 5'd4, 16'd1 };                   //R4 <- R4-1   
    IMEM[6] = { SW, 5'd4, 5'd3, 16'd0 };                      //M[R4] <- R3
    IMEM[7] = { BNEZ, 5'd4, 5'd0, 16'd4 };                    // R4 != 0 ? Jump to 4
    IMEM[8] = { MVI , 5'd0, 5'd4,  16'd0 };                   //R4<-0
    IMEM[9] = { LW, 5'd4, 5'd3, 16'd0 };                      //  R3 <- M[R4] 
    IMEM[10] = { ADDI , 5'd4, 5'd4, 16'd1 };                  // R4 <- R4+1
    IMEM[11] = { EQ , 5'd3, 5'd2, 5'd6, 11'd0 };              // R6 <- R3 == R2
    IMEM[12] = {NOP, 26'd0};          	                       //NOP 
    IMEM[13] = { BNEZ, 5'd6, 5'd0, 16'd19 };                  // R6 != 0 ? Jump to 19
    IMEM[14] = { EQI , 5'd4, 5'd7, 16'd9 };                   // R7 <- R4 == 9
    IMEM[15] = {NOP, 26'd0};          	                       //NOP
    IMEM[16] = { BEQZ, 5'd7, 5'd0, 16'd9 };                   // R7 == 0 ? Jump to 9
    IMEM[17] = { MVI , 5'd0, 5'd5,  16'h00ff };               //R5 <- failure
    IMEM[18] = { HALT , 26'd0 };                              //HALT   
    IMEM[19] = { MVI , 5'd0, 5'd5,  16'hff00 };               //R5 <- success
    IMEM[20] = { HALT , 26'd0 };                              //HALT
    */
    /*** Basic Program Branch  (Returns the number of occurences of a number in an array)************************************
    IMEM[0] = { MVI , 5'd0, 5'd31, -16'd1 };                   //R31 <- -1 ;
    IMEM[1] = { MVI , 5'd0, 5'd1, 16'd10 };                   //R1 <- 10 ; ********** SEED POINT
    IMEM[2] = { MV , 5'd1, 5'd0,  5'd2,11'd0  };              //R2<-R1
    IMEM[3] = { SUBI , 5'd1, 5'd1, 16'd1 };                   //R1 <- R1-1 
    IMEM[4] = { ADDI , 5'd31, 5'd31, 16'd1 };                   //R31 <- R31+1
    IMEM[5] = { SW, 5'd31, 5'd1, 16'd0 };                      //M[R31] <- R1
    IMEM[6] = { SUBI , 5'd2, 5'd2, 16'd1 };                   //R2 <- R2-1 
    IMEM[7] = { NOP , 26'd0 };                                //NOP
    IMEM[8] = { BNEZ, 5'd2, 5'd0, 16'd4 };                  // R2 != 0 ? Jump to 4
    IMEM[9] = { BNEZ, 5'd1, 5'd0, 16'd2 };                  // R1 != 0 ? Jump to 2
    
    IMEM[10] = { MVI , 5'd0, 5'd30, 16'd5 };                   //R30 <- 5 ;QUERY**************
    IMEM[11] = { MVI , 5'd0, 5'd29, 16'd0 };                  //R29 <- 0 ; Count number of matches -1
    
    IMEM[12] = { LW ,5'd31, 5'd2, 16'd0 };                      //  R2 <- M[R31]
    IMEM[13] = { SUBI , 5'd31, 5'd31, 16'd1 };                   //R31 <- R31-1
    IMEM[14] = { EQI , 5'd31, 5'd7, -16'd1 };                   //  R7 <- R31 == -1
    IMEM[15] = { NOP , 26'd0 };                                //NOP
    IMEM[16] = { BNEZ, 5'd7, 5'd0, 16'd26 };                   // R7 != 0 ? Jump to 26
    IMEM[17] = { EQ , 5'd30, 5'd2, 5'd6, 11'd0 };              // R6 <- R30 == R2
    IMEM[18] = { NOP , 26'd0 };                                //NOP
    IMEM[19] = { BEQZ, 5'd6, 5'd0, 16'd12 };                   // R6 == 0 ? Jump to 12
    IMEM[20] = { ADDI , 5'd29, 5'd29, 16'd1 };                   //R29<- R29+1
    IMEM[21] = {J , 26'd12 };                                    //Jump to 12
    IMEM[22] = { NOP , 26'd0 };                                //NOP
    IMEM[23] = { NOP , 26'd0 };                                //NOP
    IMEM[24] = { NOP , 26'd0 };                                //NOP
    IMEM[25] = { NOP , 26'd0 };                                //NOP
    IMEM[26] = { HALT , 26'd0 };                              //HALT 
    */
  end
  
  always @ (posedge clk) begin
    if (~stall) begin // the first three pipeline stages stall if there is a load hazard
    // IF STAGE
    if (~branchtaken) begin
      IF_ID_IR  <= IMEM[PC];
      PC        <= PC + 1;
    end else begin
      IF_ID_IR <= 32'd0;
      if(IF_ID_IR[0:5] == BEQZ | IF_ID_IR[0:5] == BNEZ) begin
        PC <= { {16{IF_ID_IR[16]}},IF_ID_IR[16:31]};  
      end else if(IF_ID_IR[0:5] == J) begin
        PC <= { {6{IF_ID_IR[6]}},IF_ID_IR[6:31]}; 
      end else if(IF_ID_IR[0:5] == JR) begin 
        PC <= REGFILE[IF_ID_IR[6:10]];
      end else if(IF_ID_IR[0:5] == CALL) begin
        REGFILE[31] <= PC;  
        PC <= { {6{IF_ID_IR[6]}},IF_ID_IR[6:31]}; 
      end else if(IF_ID_IR[0:5] == CALLR)   begin
        REGFILE[31] <= PC;
        PC <= REGFILE[IF_ID_IR[6:10]];
      end   
    end   
    
    // ID STAGE
    if(MEM_WB_IR[0:5] != SW && (IF_ID_IR[6:10] != 5'd0) && (IF_ID_IR[6:10] == MEM_WB_IR[11:15] | IF_ID_IR[6:10] == MEM_WB_IR[16:20])) begin
      ID_EX_A <= MEM_WB_ALUOUTPUT; 
    end else begin 
      ID_EX_A     <= REGFILE[IF_ID_IR[6:10]]; 
    end
    if(MEM_WB_IR[0:5] != SW && (IF_ID_IR[11:15] != 5'd0) && (IF_ID_IR[11:15] == MEM_WB_IR[11:15] | IF_ID_IR[11:15] == MEM_WB_IR[16:20])) begin
      ID_EX_B <= MEM_WB_ALUOUTPUT; 
    end else begin 
      ID_EX_B     <= REGFILE[IF_ID_IR[11:15]]; 
    end 
    ID_EX_IMM   <= { {16{IF_ID_IR[16]}},IF_ID_IR[16:31]};  
    ID_EX_IR    <= IF_ID_IR; 
    ID_EX_NPC   <= IF_ID_NPC;
    
    // EX STAGE 
    case (ID_EX_OP)
				  LW , LB , LBU , LH:                    begin EX_MEM_ALUOUTPUT <= Ain + ID_EX_IMM; EX_MEM_COND <= 0; end
				  SW , SB , SH:           	              begin EX_MEM_ALUOUTPUT <= Ain + ID_EX_IMM; EX_MEM_COND <= 0; end  
					ADD  :                                 begin EX_MEM_ALUOUTPUT <= Ain + Bin; EX_MEM_COND <= 0; end
					SUB  :                                 begin EX_MEM_ALUOUTPUT <= Ain - Bin;	EX_MEM_COND <= 0; end	  
					MULT :                                 begin EX_MEM_ALUOUTPUT <= Ain * Bin;	EX_MEM_COND <= 0; end					 
					DIV  : 			                             begin EX_MEM_ALUOUTPUT <= Ain / Bin; EX_MEM_COND <= 0; end
			    AND  : 	                               begin EX_MEM_ALUOUTPUT <= Ain & Bin;	EX_MEM_COND <= 0; end 
					OR   : 	                               begin EX_MEM_ALUOUTPUT <= Ain | Bin;	EX_MEM_COND <= 0; end  	 			
					XOR  : 	                               begin EX_MEM_ALUOUTPUT <= Ain ^ Bin; EX_MEM_COND <= 0; end
					SLT  :                                 begin
					                                       if(Ain < Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end
					SGT  :                                 begin
					                                       if(Ain > Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 			
					                                       EX_MEM_COND <= 0; 
					                                       end	  
					SLE  :                                 begin
					                                       if(Ain <= Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end					  
					SGE  :                                 begin
					                                       if(Ain >= Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end					 
					EQ  :                                  begin
					                                       if(Ain == Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end					 
					NEQ  :                                 begin
					                                       if(Ain != Bin) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end					   
					MV  :                                  begin EX_MEM_ALUOUTPUT <= Ain; EX_MEM_COND <= 0; end			  	  
					ADDI :                                 begin EX_MEM_ALUOUTPUT <= Ain + ID_EX_IMM; EX_MEM_COND <= 0; end					  
					SUBI :                                 begin EX_MEM_ALUOUTPUT <= Ain - ID_EX_IMM;	 EX_MEM_COND <= 0; end					   
					MULTI :                                begin EX_MEM_ALUOUTPUT <= Ain * ID_EX_IMM;	 EX_MEM_COND <= 0; end					 
					DIVI :                                 begin EX_MEM_ALUOUTPUT <= Ain / ID_EX_IMM; EX_MEM_COND <= 0; end					 
			    ANDI :                                 begin EX_MEM_ALUOUTPUT <= Ain & ID_EX_IMM;	EX_MEM_COND <= 0; end						  
					ORI :                                  begin EX_MEM_ALUOUTPUT <= Ain | ID_EX_IMM;	 EX_MEM_COND <= 0; end					 			
					XORI :                                 begin EX_MEM_ALUOUTPUT <= Ain ^ ID_EX_IMM; EX_MEM_COND <= 0; end					 
					SLTI  :                                begin 
					                                       if(Ain < ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end
					SGTI  :                                begin 
					                                       if(Ain > ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end
					                                       EX_MEM_COND <= 0; 
					                                       end 				  
					SLEI  :                                begin 
					                                       if(Ain <= ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 		
					                                       EX_MEM_COND <= 0; 
					                                       end			  
					SGEI  :                                begin 
					                                       if(Ain >= ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 	
					                                       EX_MEM_COND <= 0; 
					                                       end				 
					EQI  :                                 begin 
					                                       if(Ain == ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end					 
					NEQI  :                                begin 
					                                       if(Ain != ID_EX_IMM) begin 
					                                         EX_MEM_ALUOUTPUT <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT <= 0; 
					                                       end 
					                                       EX_MEM_COND <= 0; 
					                                       end				  //REGFILE
					MVI  :                                 begin EX_MEM_ALUOUTPUT <= ID_EX_IMM; EX_MEM_COND <= 0; end			   
					RET:                                   begin EX_MEM_ALUOUTPUT <= REGFILE[31]; EX_MEM_COND = 0; end					  
					NOP:                                   EX_MEM_COND <= 0;
					HALT:                                  begin 
					                                           finish =1; 
					                                           end 
					default: begin end
			endcase
			EX_MEM_IR <= ID_EX_IR; EX_MEM_B <= Bin; 
			
			end
      else EX_MEM_IR <= 32'd0; //Freeze first three stages of pipeline; inject a nop into the EX_MEM_IR
  
      //MEM STAGE
      if (EX_MEM_OP == LW || EX_MEM_OP == LB || EX_MEM_OP == LBU || EX_MEM_OP == LH) MEM_WB_LMD <= DMEM[EX_MEM_ALUOUTPUT];
      else if (EX_MEM_OP == SW || EX_MEM_OP == SB || EX_MEM_OP == SH) DMEM[EX_MEM_ALUOUTPUT] <= EX_MEM_B; 
      MEM_WB_IR <= EX_MEM_IR; 
      MEM_WB_ALUOUTPUT <= EX_MEM_ALUOUTPUT;

      //WB STAGE
      case(MEM_WB_OP)
			    ADD, SUB , MULT, DIV ,AND ,OR , XOR ,SLT,SGT ,SLE, SGE ,EQ ,   NEQ , MV : REGFILE[MEM_WB_IR[16:20]] <=  MEM_WB_ALUOUTPUT;				 
				  ADDI, SUBI , MULTI, DIVI ,ANDI ,ORI , XORI ,SLTI ,SGTI ,SLEI , SGEI ,EQI , NEQI , MVI : REGFILE[MEM_WB_IR[11:15]] <=  MEM_WB_ALUOUTPUT;    
				  LW , LB , LBU , LH :    REGFILE[MEM_WB_IR[11:15]] = MEM_WB_LMD;				     				   
		  endcase
end
endmodule 
