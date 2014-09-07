module superscalar_cpu(clk);
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
  ** Superscalar Degree : 2
  ****************************************************************/ 
  parameter INSTRUCTION_MEMORY_SIZE = 10  ; parameter REGISTER_FILE_SIZE  =  5; 
  parameter OPC             = 6   ; parameter DATA_MEMORY_SIZE    = 10;   
  parameter S_DEGREE = 2;
  
  reg [ 0:31  ]     IMEM    [0: 2 ** INSTRUCTION_MEMORY_SIZE  -1 ] ;	   // Instruction Memory
  reg [ 0:31  ]     DMEM    [0: 2 ** DATA_MEMORY_SIZE         -1 ];	    // Data Memory
  reg [ 0:31  ]     REGFILE [0: 2 ** REGISTER_FILE_SIZE       -1 ];	    // General Purpose Registers
  reg [ 0 : INSTRUCTION_MEMORY_SIZE  -1]  PC;			                        // program counter

  /***************************************************   Pipeline Registers  ********************************************/
                                /************Pipeline Registers : IF Stage *****************/
  reg [ 0:31  ] IF_ID_IR[0:S_DEGREE-1]  ;   
  
                                /************Pipeline Registers : ID Stage **************/                                                    
  reg [ 0:31  ] ID_EX_IR[0:S_DEGREE-1], ID_EX_A[0:S_DEGREE-1], ID_EX_B[0:S_DEGREE-1], ID_EX_IMM[0:S_DEGREE-1];
                                                                            
                                /************Pipeline Registers : EX Stage *****************/   
  reg [ 0:31  ] EX_MEM_IR[0:S_DEGREE-1],                       EX_MEM_B[0:S_DEGREE-1],        EX_MEM_ALUOUTPUT[0:S_DEGREE-1];	
                                                     
                                /************Pipeline Registers : MEM Stage *****************/            
  reg [ 0:31  ] MEM_WB_IR[0:S_DEGREE-1],                                                      MEM_WB_ALUOUTPUT[0:S_DEGREE-1], MEM_WB_LMD[0:S_DEGREE-1];  
                                                      
                                                        
                                /*********** Opcode Registers *********************************/
  wire [0 : OPC -1] EX_MEM_OP[0:S_DEGREE-1], MEM_WB_OP[0:S_DEGREE-1];  //Access opcodes
  wire [0 : OPC -1] ID_EX_OP[0:S_DEGREE-1],  IF_ID_OP[0:S_DEGREE-1];   //Access opcodes
  wire [0:31] Ain[0:S_DEGREE-1], Bin[0:S_DEGREE-1];                           //The ALU inputs

                                /************ Bypassing Registers ********************************/
  wire [0:REGISTER_FILE_SIZE - 1] ID_EX_rs[0:S_DEGREE-1], ID_EX_rt[0:S_DEGREE-1];       //Sources
  wire [0:REGISTER_FILE_SIZE - 1] EX_MEM_rd[0:S_DEGREE-1], MEM_WB_rd[0:S_DEGREE-1];     //Destinations
  wire bypassAfrom_EX_MEM[0:S_DEGREE-1][0:S_DEGREE-1], bypassAfrom_MEM_WB[0:S_DEGREE-1][0:S_DEGREE-1]; //Bypass Signals from EX_MEM & 
                                                                                                       //MEM_WB stage for source A
  wire bypassBfrom_EX_MEM[0:S_DEGREE-1][0:S_DEGREE-1], bypassBfrom_MEM_WB[0:S_DEGREE-1][0:S_DEGREE-1]; //Bypass Signals from EX_MEM & 
                                                                                                       //MEM_WB stage for source B                                                                                                        
  wire bypassAfromLWin_MEM_WB[0:S_DEGREE-1][0:S_DEGREE-1], bypassBfromLWin_MEM_WB[0:S_DEGREE-1][0:S_DEGREE-1]; //Bypass Signals from Load 
                                                                                                              //instructions     
  
                                /************ Branch Prediction Registers ********************************/
  wire bypassAfromEX_MEMforbranch[0:S_DEGREE-1][0:S_DEGREE-1],  
                                            bypassAfromMEM_WBforbranch[0:S_DEGREE-1][0:S_DEGREE-1]; //Bypass signals for branch instructions                                   
  wire branchtaken[0:S_DEGREE-1];
  wire [0:REGISTER_FILE_SIZE - 1] IF_ID_rs[0:S_DEGREE-1]; //Sources

  
  /*****************************************  At each stage determining the opcodes *********************************************/
  assign IF_ID_OP[0] = IF_ID_IR[0][0:OPC -1]; assign IF_ID_OP[1]  = IF_ID_IR[1][0:OPC -1];
  assign ID_EX_OP[0] = ID_EX_IR[0][0:OPC -1]; assign ID_EX_OP[1]  = ID_EX_IR[1][0:OPC -1];
  assign EX_MEM_OP[0] = EX_MEM_IR[0][0:OPC -1]; assign EX_MEM_OP[1]  = EX_MEM_IR[1][0:OPC -1];
  assign MEM_WB_OP[0] = MEM_WB_IR[0][0:OPC -1]; assign MEM_WB_OP[1]  = MEM_WB_IR[1][0:OPC -1];
  
  /**************************************** Detection for Conflict between symultaneous issues's ALU operations************************/
  wire [0:REGISTER_FILE_SIZE - 1]first_instr_destination;
  wire [0:REGISTER_FILE_SIZE - 1]second_instr_source_1, second_instr_source_2; 
  wire one_cycle_stall;
  assign first_instr_destination = (IF_ID_OP[0] >= ADDI && IF_ID_OP[0] <= MVI) | IF_ID_OP[0] == LW
                                   ? IF_ID_IR[0][11:15] : (IF_ID_OP[0] >= ADD && IF_ID_OP[0] <= MV) ? IF_ID_IR[0][16:20]: 32'd0;
                                   
  assign second_instr_source_1   = IF_ID_OP[1] != MVI &  IF_ID_OP[1] != J &  IF_ID_OP[1] != CALL &  IF_ID_OP[1] != HALT &  IF_ID_OP[1] != RET ?
                                   IF_ID_IR[1][6:10] : 32'd0;
  assign second_instr_source_2   = IF_ID_OP[1] >= ADD && IF_ID_OP[1] <= NEQ ? IF_ID_IR[1][11:15] : 32'd0;
  assign one_cycle_stall = ( second_instr_source_1 == first_instr_destination && second_instr_source_1 != 32'd0) |  
                           ( second_instr_source_2 == first_instr_destination && second_instr_source_2 != 32'd0) ? 1 : 0;
                           
                           
 /**************************************** Detection for Load Conflict between symultaneous issues************************/
 
  wire two_cycle_stall;
  assign two_cycle_stall = IF_ID_OP[0] == LW && (second_instr_source_1 == first_instr_destination || 
                           second_instr_source_2 == first_instr_destination) && first_instr_destination != 32'd0 ;
                            
  
  /**************************************** Computation for Data-forwarding ***********************************************/
  //Computing Source 'A' form the ID_EX register for the current instruction. 
  assign ID_EX_rs[0] = ID_EX_IR[0][6:10];   assign ID_EX_rs[1] = ID_EX_IR[1][6:10]; 
  
  //Computing Source 'B' form the ID_EX register for the current instruction. 
  assign ID_EX_rt[0] = ID_EX_IR[0][11:15];  assign ID_EX_rt[1] = ID_EX_IR[1][11:15];
  
  //Destination at EX_MEM Stage
  assign EX_MEM_rd[0] = EX_MEM_OP[0] >= ADDI & EX_MEM_OP[0] <= MVI ? EX_MEM_IR[0][11:15] : EX_MEM_IR[0][16:20];
  assign EX_MEM_rd[1] = EX_MEM_OP[1] >= ADDI & EX_MEM_OP[1] <= MVI ? EX_MEM_IR[1][11:15] : EX_MEM_IR[1][16:20];
  
  //Destination at MEM_WB Stage
  assign MEM_WB_rd[0] = MEM_WB_OP[0] >= ADDI & MEM_WB_OP[0] <= MVI ? MEM_WB_IR[0][11:15] : MEM_WB_IR[0][16:20];
  assign MEM_WB_rd[1] = MEM_WB_OP[1] >= ADDI & MEM_WB_OP[1] <= MVI ? MEM_WB_IR[1][11:15] : MEM_WB_IR[1][16:20];
  

  // Bypassing source operand 'A' from the EX_MEM buffer of the previous instruction to the ID_EX operands
  //Note: MVI doesn't make any sense for 'A' frwding
  
  //case 00: current 0th instruction gets value farwarded from previous 0th instruction.
  assign bypassAfrom_EX_MEM[0][0] = (ID_EX_rs[0] == EX_MEM_rd[0]) & (ID_EX_rs[0]!=0) & (EX_MEM_OP[0] >= ADD & 
                                     EX_MEM_OP[0] <= MVI) & (ID_EX_OP[0] != MVI);
  //case 01: current 0th instruction gets value farwarded from previous 1th instruction.
  assign bypassAfrom_EX_MEM[0][1] = (ID_EX_rs[0] == EX_MEM_rd[1]) & (ID_EX_rs[0]!=0) & (EX_MEM_OP[1] >= ADD & 
                                     EX_MEM_OP[1] <= MVI) & (ID_EX_OP[0] != MVI);
                                     
  //case 10: current 1th instruction gets value farwarded from previous 0th instruction.
  assign bypassAfrom_EX_MEM[1][0] = (ID_EX_rs[1] == EX_MEM_rd[0]) & (ID_EX_rs[1]!=0) & (EX_MEM_OP[0] >= ADD & 
                                     EX_MEM_OP[0] <= MVI) & (ID_EX_OP[1] != MVI);
  //case 11: current 1th instruction gets value farwarded from previous 1th instruction.
  assign bypassAfrom_EX_MEM[1][1] = (ID_EX_rs[1] == EX_MEM_rd[1]) & (ID_EX_rs[1]!=0) & (EX_MEM_OP[1] >= ADD & 
                                     EX_MEM_OP[1] <= MVI) & (ID_EX_OP[1] != MVI);
                                     
  //Bypassing source operand 'B' from the EX_MEM buffer of the previous instruction to the ID_EX operands  
  //Note : MVI, MV, or any alu immediate instruction doesn't make any sense for 'B' frwding                                                                   
  assign bypassBfrom_EX_MEM[0][0] = (ID_EX_rt[0]== EX_MEM_rd[0])&(ID_EX_rt[0]!=0) & (EX_MEM_OP[0] >= ADD & 
                                     EX_MEM_OP[0] <= MVI) & !(ID_EX_OP[0] >= ADDI & ID_EX_OP[0] <= MVI) & (ID_EX_OP[0] != MV) ;
  assign bypassBfrom_EX_MEM[0][1] = (ID_EX_rt[0]== EX_MEM_rd[1])&(ID_EX_rt[0]!=0) & (EX_MEM_OP[1] >= ADD & 
                                     EX_MEM_OP[1] <= MVI) & !(ID_EX_OP[0] >= ADDI & ID_EX_OP[0] <= MVI) & (ID_EX_OP[0] != MV) ;
  assign bypassBfrom_EX_MEM[1][0] = (ID_EX_rt[1]== EX_MEM_rd[0])&(ID_EX_rt[1]!=0) & (EX_MEM_OP[0] >= ADD & 
                                     EX_MEM_OP[0] <= MVI) & !(ID_EX_OP[1] >= ADDI & ID_EX_OP[1] <= MVI) & (ID_EX_OP[1] != MV) ;
  assign bypassBfrom_EX_MEM[1][1] = (ID_EX_rt[1]== EX_MEM_rd[1])&(ID_EX_rt[1]!=0) & (EX_MEM_OP[1] >= ADD & 
                                     EX_MEM_OP[1] <= MVI) & !(ID_EX_OP[1] >= ADDI & ID_EX_OP[1] <= MVI) & (ID_EX_OP[1] != MV) ;
                                                           
  
  //Bypassing source operand 'A' from the MEM_WB buffer of the previous instruction to the ID_EX operands
  //Note: MVI doesn't make any sense for 'A' frwding
  assign bypassAfrom_MEM_WB[0][0] = (ID_EX_rs[0] == MEM_WB_rd[0]) & (ID_EX_rs[0]!=0) & (MEM_WB_OP[0] >= ADD & 
                                     MEM_WB_OP[0] <= MVI) & (ID_EX_OP[0] != MVI);
  assign bypassAfrom_MEM_WB[0][1] = (ID_EX_rs[0] == MEM_WB_rd[1]) & (ID_EX_rs[0]!=0) & (MEM_WB_OP[1] >= ADD & 
                                     MEM_WB_OP[1] <= MVI) & (ID_EX_OP[0] != MVI);                             
  assign bypassAfrom_MEM_WB[1][0] = (ID_EX_rs[1] == MEM_WB_rd[0]) & (ID_EX_rs[1]!=0) & (MEM_WB_OP[0] >= ADD & 
                                     MEM_WB_OP[0] <= MVI) & (ID_EX_OP[1] != MVI);
  assign bypassAfrom_MEM_WB[1][1] = (ID_EX_rs[1] == MEM_WB_rd[1]) & (ID_EX_rs[1]!=0) & (MEM_WB_OP[1] >= ADD & 
                                     MEM_WB_OP[1] <= MVI) & (ID_EX_OP[1] != MVI);
   
  //Bypassing source operand 'B' from the MEM_WB buffer of the previous instruction to the ID_EX operands  
  //Note : MVI, MV, or any alu immediate instruction doesn't make any sense for 'B' frwding                                                                   
  assign bypassBfrom_MEM_WB[0][0] = (ID_EX_rt[0]== MEM_WB_rd[0])&(ID_EX_rt[0]!=0) & (MEM_WB_OP[0] >= ADD & 
                                     MEM_WB_OP[0] <= MVI) & !(ID_EX_OP[0] >= ADDI & ID_EX_OP[0] <= MVI) & (ID_EX_OP[0] != MV) ;
  assign bypassBfrom_MEM_WB[0][1] = (ID_EX_rt[0]== MEM_WB_rd[1])&(ID_EX_rt[0]!=0) & (MEM_WB_OP[1] >= ADD & 
                                     MEM_WB_OP[1] <= MVI) & !(ID_EX_OP[0] >= ADDI & ID_EX_OP[0] <= MVI) & (ID_EX_OP[0] != MV) ;
  assign bypassBfrom_MEM_WB[1][0] = (ID_EX_rt[1]== MEM_WB_rd[0])&(ID_EX_rt[1]!=0) & (MEM_WB_OP[0] >= ADD & 
                                     MEM_WB_OP[0] <= MVI) & !(ID_EX_OP[1] >= ADDI & ID_EX_OP[1] <= MVI) & (ID_EX_OP[1] != MV) ;
  assign bypassBfrom_MEM_WB[1][1] = (ID_EX_rt[1]== MEM_WB_rd[1])&(ID_EX_rt[1]!=0) & (MEM_WB_OP[1] >= ADD & 
                                     MEM_WB_OP[1] <= MVI) & !(ID_EX_OP[1] >= ADDI & ID_EX_OP[1] <= MVI) & (ID_EX_OP[1] != MV) ;                                  
                          
 
  // The bypass to input A in ID_EX buffer from the MEM_WB buffer corresponding to LW operation.
  assign bypassAfromLWin_MEM_WB[0][0] =( ID_EX_rs[0] == MEM_WB_IR[0][11:15]) & (ID_EX_rs[0]!=0) & (MEM_WB_OP[0] >= LW && MEM_WB_OP[0] <= LH);
  assign bypassAfromLWin_MEM_WB[0][1] =( ID_EX_rs[0] == MEM_WB_IR[1][11:15]) & (ID_EX_rs[0]!=0) & (MEM_WB_OP[1] >= LW && MEM_WB_OP[1] <= LH);
  assign bypassAfromLWin_MEM_WB[1][0] =( ID_EX_rs[1] == MEM_WB_IR[0][11:15]) & (ID_EX_rs[1]!=0) & (MEM_WB_OP[0] >= LW && MEM_WB_OP[0] <= LH);
  assign bypassAfromLWin_MEM_WB[1][1] =( ID_EX_rs[1] == MEM_WB_IR[1][11:15]) & (ID_EX_rs[1]!=0) & (MEM_WB_OP[1] >= LW && MEM_WB_OP[1] <= LH);
 
                            
  // The bypass to input B   in ID_EX buffer from the MEM_WB buffer corresponding to LW operation.
  assign bypassBfromLWin_MEM_WB[0][0] =( ID_EX_rt[0] == MEM_WB_IR[0][11:15]) & (ID_EX_rt[0]!=0) & (MEM_WB_OP[0] >= LW && MEM_WB_OP[0] <= LH);
  assign bypassBfromLWin_MEM_WB[0][1] =( ID_EX_rt[0] == MEM_WB_IR[1][11:15]) & (ID_EX_rt[0]!=0) & (MEM_WB_OP[1] >= LW && MEM_WB_OP[1] <= LH);
  assign bypassBfromLWin_MEM_WB[1][0] =( ID_EX_rt[1] == MEM_WB_IR[0][11:15]) & (ID_EX_rt[1]!=0) & (MEM_WB_OP[0] >= LW && MEM_WB_OP[0] <= LH);
  assign bypassBfromLWin_MEM_WB[1][1] =( ID_EX_rt[1] == MEM_WB_IR[1][11:15]) & (ID_EX_rt[1]!=0) & (MEM_WB_OP[1] >= LW && MEM_WB_OP[1] <= LH);
   
  /*The A input to the ALU is bypassed from previous 1th instructions' EX_MEM buffer or
                                       from previous 0th instructions' EX_MEM buffer or
                                       from previous 1th instructions' MEM_WB buffer or
                                       from previous 0th instructions' MEM_WB buffer or
                                       from previous 1th instructions'(load instruction) MEM_WB buffer or
                                       from previous 0th instructions'(load instruction) MEM_WB buffer or
                                       from the current instyructions' registers.
  */                                     
  assign Ain[0] = bypassAfrom_EX_MEM[0][1]? EX_MEM_ALUOUTPUT[1] : bypassAfrom_EX_MEM[0][0] ? EX_MEM_ALUOUTPUT[0] :  
                  bypassAfrom_MEM_WB[0][1] ? MEM_WB_ALUOUTPUT[1] : bypassAfrom_MEM_WB[0][0] ? MEM_WB_ALUOUTPUT[0]: 
                  bypassAfromLWin_MEM_WB[0][1] ? MEM_WB_LMD[1] : bypassAfromLWin_MEM_WB[0][0] ? MEM_WB_LMD[0] :
                  ID_EX_A[0];
                  
  assign Ain[1] = bypassAfrom_EX_MEM[1][1]     ? EX_MEM_ALUOUTPUT[1] : bypassAfrom_EX_MEM[1][0] ? EX_MEM_ALUOUTPUT[0] :  
                  bypassAfrom_MEM_WB[1][1]     ? MEM_WB_ALUOUTPUT[1] : bypassAfrom_MEM_WB[1][0] ? MEM_WB_ALUOUTPUT[0]: 
                  bypassAfromLWin_MEM_WB[1][1] ? MEM_WB_LMD[1]       : bypassAfromLWin_MEM_WB[1][0] ? MEM_WB_LMD[0] :
                  ID_EX_A[1];
                  
  /*The B input to the ALU is bypassed from previous 1th instructions' EX_MEM buffer or
                                       from previous 0th instructions' EX_MEM buffer or
                                       from previous 1th instructions' MEM_WB buffer or
                                       from previous 0th instructions' MEM_WB buffer or
                                       from previous 1th instructions'(load instruction) MEM_WB buffer or
                                       from previous 0th instructions'(load instruction) MEM_WB buffer or
                                       from the current instyructions' registers.
  */
  assign Bin[0] = bypassBfrom_EX_MEM[0][1]? EX_MEM_ALUOUTPUT[1] : bypassBfrom_EX_MEM[0][0] ? EX_MEM_ALUOUTPUT[0] :  
                  bypassBfrom_MEM_WB[0][1] ? MEM_WB_ALUOUTPUT[1] : bypassBfrom_MEM_WB[0][0] ? MEM_WB_ALUOUTPUT[0]: 
                  bypassBfromLWin_MEM_WB[0][1] ? MEM_WB_LMD[1] : bypassBfromLWin_MEM_WB[0][0] ? MEM_WB_LMD[0] :
                  ID_EX_B[0];
                  
  assign Bin[1] = bypassBfrom_EX_MEM[1][1]     ? EX_MEM_ALUOUTPUT[1] : bypassBfrom_EX_MEM[1][0] ? EX_MEM_ALUOUTPUT[0] :  
                  bypassBfrom_MEM_WB[1][1]     ? MEM_WB_ALUOUTPUT[1] : bypassBfrom_MEM_WB[1][0] ? MEM_WB_ALUOUTPUT[0]: 
                  bypassBfromLWin_MEM_WB[1][1] ? MEM_WB_LMD[1]       : bypassBfromLWin_MEM_WB[1][0] ? MEM_WB_LMD[0] :
                  ID_EX_B[1];
                  
  /**************************************** Computation for Branch Prediction ***********************************************/               
  //Branch decision is taken at the begining of the ID stage and forwarding (if necessary) is to be done from ID_EX, EX_MEM, and MEM_WB buffers
  //Also the instruction forwarding the result should not be SW.    
  //For conditional branch instruction the source register(say R1)(eq. BNEZ R1, ADDR), need to be read and hence forwarding may be needed
  //from the EX_MEM stage or from the MEM_WB stage.(NOT FROM THE ID_EX, AS ITS NOT READY BY THEN).
  
  assign IF_ID_OP[0] = IF_ID_IR[0][0:OPC -1]; assign IF_ID_OP[1]  = IF_ID_IR[1][0:OPC -1];
  assign IF_ID_rs[0]  = IF_ID_IR[0][6:10]; assign IF_ID_rs[1]  = IF_ID_IR[1][6:10];
  
  assign bypassAfromEX_MEMforbranch[0][0] = (IF_ID_rs[0] == EX_MEM_rd[0]) & (IF_ID_rs[0]!=0) & (EX_MEM_OP[0] >= ADD & EX_MEM_OP[0] <= MVI) & 
                                            (IF_ID_OP[0] == BNEZ | IF_ID_OP[0] == BEQZ);
  assign bypassAfromEX_MEMforbranch[0][1] = (IF_ID_rs[0] == EX_MEM_rd[1]) & (IF_ID_rs[0]!=0) & (EX_MEM_OP[1] >= ADD & EX_MEM_OP[1] <= MVI) & 
                                            (IF_ID_OP[0] == BNEZ | IF_ID_OP[0] ==BEQZ);
  assign bypassAfromEX_MEMforbranch[1][0] = (IF_ID_rs[1] == EX_MEM_rd[0]) & (IF_ID_rs[1]!=0) & (EX_MEM_OP[0] >= ADD & EX_MEM_OP[0] <= MVI) & 
                                            (IF_ID_OP[1] == BNEZ | IF_ID_OP[1] ==BEQZ);
  assign bypassAfromEX_MEMforbranch[1][1] = (IF_ID_rs[1] == EX_MEM_rd[1]) & (IF_ID_rs[1]!=0) & (EX_MEM_OP[1] >= ADD & EX_MEM_OP[1] <= MVI) & 
                                            (IF_ID_OP[1] == BNEZ | IF_ID_OP[1] ==BEQZ);                                                                                    
   
   
  assign bypassAfromMEM_WBforbranch[0][0] = (IF_ID_rs[0] == MEM_WB_rd[0]) & (IF_ID_rs[0]!=0) & (MEM_WB_OP[0] >= ADD & MEM_WB_OP[0] <= MVI) & 
                                            (IF_ID_OP[0] == BNEZ | IF_ID_OP[0] ==BEQZ);
  assign bypassAfromMEM_WBforbranch[0][1] = (IF_ID_rs[0] == MEM_WB_rd[1]) & (IF_ID_rs[0]!=0) & (MEM_WB_OP[1] >= ADD & MEM_WB_OP[1] <= MVI) & 
                                            (IF_ID_OP[0] == BNEZ | IF_ID_OP[0] ==BEQZ);
  assign bypassAfromMEM_WBforbranch[1][0] = (IF_ID_rs[1] == MEM_WB_rd[0]) & (IF_ID_rs[1]!=0) & (MEM_WB_OP[0] >= ADD & MEM_WB_OP[0] <= MVI) & 
                                            (IF_ID_OP[1] == BNEZ | IF_ID_OP[1] ==BEQZ);
  assign bypassAfromMEM_WBforbranch[1][1] = (IF_ID_rs[1] == MEM_WB_rd[1]) & (IF_ID_rs[1]!=0) & (MEM_WB_OP[1] >= ADD & MEM_WB_OP[1] <= MVI) & 
                                            (IF_ID_OP[1] == BNEZ | IF_ID_OP[1] ==BEQZ);                                   
                      
  assign branchtaken[0] = ((IF_ID_IR[0][0:5] == BEQZ) && (bypassAfromEX_MEMforbranch[0][1] ? EX_MEM_ALUOUTPUT[1] == 32'd0 : 
                                                          bypassAfromEX_MEMforbranch[0][0] ? EX_MEM_ALUOUTPUT[0] == 32'd0:
                                                          bypassAfromMEM_WBforbranch[0][1] ? MEM_WB_ALUOUTPUT[1] == 32'd0:
                                                          bypassAfromMEM_WBforbranch[0][0] ? MEM_WB_ALUOUTPUT[0] == 32'd0:
                                                          REGFILE[IF_ID_IR[0][6:10]] == 32'd0)) 
                                                      ||
                          ((IF_ID_IR[0][0:5] == BNEZ) && (bypassAfromEX_MEMforbranch[0][1] ? EX_MEM_ALUOUTPUT[1] != 32'd0 : 
                                                          bypassAfromEX_MEMforbranch[0][0] ? EX_MEM_ALUOUTPUT[0] != 32'd0:
                                                          bypassAfromMEM_WBforbranch[0][1] ? MEM_WB_ALUOUTPUT[1] != 32'd0:
                                                          bypassAfromMEM_WBforbranch[0][0] ? MEM_WB_ALUOUTPUT[0] != 32'd0:
                                                          REGFILE[IF_ID_IR[0][6:10]] != 32'd0))                                                                           
                                                      || 
                          IF_ID_IR[0][0:5] == JR      || IF_ID_IR[0][0:5] == J || IF_ID_IR[0][0:5] == CALL || IF_ID_IR[0][0:5] == CALLR;
   
  assign branchtaken[1] = ((IF_ID_IR[1][0:5] == BEQZ) && (bypassAfromEX_MEMforbranch[1][1] ? EX_MEM_ALUOUTPUT[1] == 32'd0 : 
                                                          bypassAfromEX_MEMforbranch[1][0] ? EX_MEM_ALUOUTPUT[0] == 32'd0:
                                                          bypassAfromMEM_WBforbranch[1][1] ? MEM_WB_ALUOUTPUT[1] == 32'd0:
                                                          bypassAfromMEM_WBforbranch[1][0] ? MEM_WB_ALUOUTPUT[0] == 32'd0:
                                                          REGFILE[IF_ID_IR[1][6:10]] == 32'd0)) 
                                                      ||
                          ((IF_ID_IR[1][0:5] == BNEZ) && (bypassAfromEX_MEMforbranch[1][1] ? EX_MEM_ALUOUTPUT[1] != 32'd0 : 
                                                          bypassAfromEX_MEMforbranch[1][0] ? EX_MEM_ALUOUTPUT[0] != 32'd0:
                                                          bypassAfromMEM_WBforbranch[1][1] ? MEM_WB_ALUOUTPUT[1] != 32'd0:
                                                          bypassAfromMEM_WBforbranch[1][0] ? MEM_WB_ALUOUTPUT[0] != 32'd0:
                                                          REGFILE[IF_ID_IR[1][6:10]] != 32'd0))                                                                           
                                                      || 
                          IF_ID_IR[1][0:5] == JR      || IF_ID_IR[1][0:5] == J || IF_ID_IR[1][0:5] == CALL || IF_ID_IR[1][0:5] == CALLR;
                          
  reg [5:0] i; 
  reg finish;
  
  /************** The initial cpu state bootstrap **************************/
  initial begin 
    PC = 0;
    finish =0;
    $readmemh("bincode.rom",IMEM);
    IF_ID_IR[0]  = 32'b0; IF_ID_IR[1]  = 32'b0;
    ID_EX_IR[0]  = 32'b0; ID_EX_IR[1]  = 32'b0;
    EX_MEM_IR[0] = 32'b0; EX_MEM_IR[1] = 32'b0;
    MEM_WB_IR[0] = 32'b0; MEM_WB_IR[1] = 32'b0;
    
    /*** Test Program Branch  ************************************/
    
    /*IMEM[0] = { MVI , 5'd0, 5'd1,  16'd0 };                  //R1 <- 2
    IMEM[1] = { MVI , 5'd0, 5'd3,  16'd0 };                  //R3 <- 0 
     
    IMEM[2] = { NOP , 26'd0 };                             //NOP
    IMEM[3] = { NOP , 26'd0 };                             //NOP
    
    IMEM[4] = { MVI , 5'd0, 5'd3,  16'd1 };                  //R3 <- 1
    IMEM[5] = { BNEZ , 5'd1, 21'd7 };                  //R1 != 0 goto 7
    
    IMEM[6] = { MVI , 5'd0, 5'd3,  16'd2 };                  //R3 <- 2  
    IMEM[7] = { HALT , 26'd0 };                              //HALT
    */
    /*** Basic Program Branch  (Returns the number of occurences of a number in an array)************************************
    IMEM[0] = { MVI , 5'd0, 5'd31, -16'd1 };                   //R31 <- -1 ;
    IMEM[1] = { MVI , 5'd0, 5'd1, 16'd10 };                   //R1 <- 10 ; ********** SEED POINT
    
    IMEM[2] = { MV , 5'd1, 5'd0,  5'd2,11'd0  };              //R2<-R1
    IMEM[3] = { SUBI , 5'd1, 5'd1, 16'd1 };                   //R1 <- R1-1 
    
    IMEM[4] = { ADDI , 5'd31, 5'd31, 16'd1 };                   //R31 <- R31+1
    IMEM[5] = { NOP , 26'd0 };
    
    IMEM[6] = { SW, 5'd31, 5'd1, 16'd0 };                      //M[R31] <- R1
    IMEM[7] = { SUBI , 5'd2, 5'd2, 16'd1 };                   //R2 <- R2-1 
    
    IMEM[8] = { NOP , 26'd0 };                                //NOP
    IMEM[9] = { NOP , 26'd0 };                                //NOP
    
    IMEM[10] = { BNEZ, 5'd2, 5'd0, 16'd4 };                  // R2 != 0 ? Jump to 4
    IMEM[11] = { NOP , 26'd0 };                                //NOP
    
    IMEM[12] = { BNEZ, 5'd1, 5'd0, 16'd2 };                  // R1 != 0 ? Jump to 2
    IMEM[13] = { NOP , 26'd0 };                                //NOP
    
    
    IMEM[14] = { MVI , 5'd0, 5'd30, 16'd5 };                   //R30 <- 5 ;QUERY**************
    IMEM[15] = { MVI , 5'd0, 5'd29, 16'd0 };                  //R29 <- 0 ; Count number of matches -1
    
    IMEM[16] = { LW ,5'd31, 5'd2, 16'd0 };                      //  R2 <- M[R31]
    IMEM[17] = { SUBI , 5'd31, 5'd31, 16'd1 };                   //R31 <- R31-1
    
    IMEM[18] = { EQI , 5'd31, 5'd7, -16'd1 };                   //  R7 <- R31 == -1
    IMEM[19] = { NOP , 26'd0 };                                //NOP
    
    IMEM[20] = { NOP , 26'd0 };                                //NOP
    IMEM[21] = { NOP , 26'd0 };                                //NOP
    
    IMEM[22] = { BNEZ, 5'd7, 5'd0, 16'd32 };                   // R7 != 0 ? Jump to 32
    IMEM[23] = { EQ , 5'd30, 5'd2, 5'd6, 11'd0 };              // R6 <- R30 == R2
    
    IMEM[24] = { NOP , 26'd0 };                                //NOP
    IMEM[25] = { NOP , 26'd0 };                                //NOP
    
    IMEM[26] = { BEQZ, 5'd6, 5'd0, 16'd16 };                   // R6 == 0 ? Jump to 16
    IMEM[27] = { NOP , 26'd0 };                                //NOP
    
    IMEM[28] = { ADDI , 5'd29, 5'd29, 16'd1 };                   //R29<- R29+1 
    IMEM[29] = {J , 26'd16 };                                    //Jump to 16
    
    IMEM[30] = { NOP , 26'd0 };                                //NOP
    IMEM[31] = { NOP , 26'd0 };                                //NOP
    
    IMEM[32] = { HALT , 26'd0 };                              //HALT
    IMEM[33] = { NOP , 26'd0 };                                //NOP
   */
  end
  
  always @ (posedge clk) begin
   //IF STAGE
      //Computation
      if (~branchtaken[0] && ~branchtaken[1]) begin
        if(one_cycle_stall) begin
          IF_ID_IR[0]  <= IMEM[PC-1];  
          IF_ID_IR[1]  <= IMEM[PC];
          PC           <= PC + 1;
        end else begin  
          IF_ID_IR[0]  <= IMEM[PC];  
          IF_ID_IR[1]  <= IMEM[PC + 1];
          PC           <= PC + 2;
        end   
      end else begin        /****We Ignore the possibility that both instructions in a single is is going to be branches****************/
         //Incur one stall for branches                   
        IF_ID_IR[0] <= 32'd0; IF_ID_IR[1] <= 32'd0;
       
        if(IF_ID_IR[0][0:5] == BEQZ | IF_ID_IR[0][0:5] == BNEZ) begin
          PC <= { {16{IF_ID_IR[0][16]}},IF_ID_IR[0][16:31]};  
        end else if(IF_ID_IR[0][0:5] == J) begin
          PC <= { {6{IF_ID_IR[0][6]}},IF_ID_IR[0][6:31]}; 
        end else if(IF_ID_IR[0][0:5] == JR) begin 
          PC <= REGFILE[IF_ID_IR[0][6:10]];
        end else if(IF_ID_IR[0][0:5] == CALL) begin
          REGFILE[31] <= PC;  
          PC <= { {6{IF_ID_IR[0][6]}},IF_ID_IR[0][6:31]}; 
        end else if(IF_ID_IR[0][0:5] == CALLR)   begin
          REGFILE[31] <= PC;
          PC <= REGFILE[IF_ID_IR[0][6:10]];
        end else if(IF_ID_IR[1][0:5] == BEQZ | IF_ID_IR[1][0:5] == BNEZ) begin
          PC <= { {16{IF_ID_IR[1][16]}},IF_ID_IR[1][16:31]};  
        end else if(IF_ID_IR[1][0:5] == J) begin
          PC <= { {6{IF_ID_IR[1][6]}},IF_ID_IR[1][6:31]}; 
        end else if(IF_ID_IR[1][0:5] == JR) begin 
          PC <= REGFILE[IF_ID_IR[1][6:10]];
        end else if(IF_ID_IR[1][0:5] == CALL) begin
          REGFILE[31] <= PC;  
          PC <= { {6{IF_ID_IR[1][6]}},IF_ID_IR[1][6:31]}; 
        end else if(IF_ID_IR[1][0:5] == CALLR)   begin
          REGFILE[31] <= PC;
          PC <= REGFILE[IF_ID_IR[1][6:10]];
        end  
      end 
      
    
    // ID STAGE  
      //Computation
      ID_EX_A[0]     <= REGFILE[IF_ID_IR[0][6:10]];
      ID_EX_A[1]     <= REGFILE[IF_ID_IR[1][6:10]];
      ID_EX_B[0]     <= REGFILE[IF_ID_IR[0][11:15]];
      ID_EX_B[1]     <= REGFILE[IF_ID_IR[1][11:15]];
      ID_EX_IMM[0]   <= { {16{IF_ID_IR[0][16]}},IF_ID_IR[0][16:31]}; 
      ID_EX_IMM[1]   <= { {16{IF_ID_IR[1][16]}},IF_ID_IR[1][16:31]}; 
      
      //Buffering
      ID_EX_IR[0]    <= IF_ID_IR[0]; 
       
      if(one_cycle_stall) begin
        ID_EX_IR[1]    <= 32'd0;
      end else begin
        ID_EX_IR[1]    <= IF_ID_IR[1];
      end
      
    // EX STAGE 
      //Computation
      case (ID_EX_OP[0])
				  LW , LB , LBU , LH:                    begin EX_MEM_ALUOUTPUT[0] <= Ain[0] + ID_EX_IMM[0];  end
				  SW , SB , SH:           	              begin EX_MEM_ALUOUTPUT[0] <= Ain[0] + ID_EX_IMM[0];  end  
					ADD  :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] + Bin[0];  end
					SUB  :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] - Bin[0];	 end	  
					MULT :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] * Bin[0];	 end					 
					DIV  : 			                             begin EX_MEM_ALUOUTPUT[0] <= Ain[0] / Bin[0];  end
			    AND  : 	                               begin EX_MEM_ALUOUTPUT[0] <= Ain[0] & Bin[0];	 end 
					OR   : 	                               begin EX_MEM_ALUOUTPUT[0] <= Ain[0] | Bin[0];	 end  	 			
					XOR  : 	                               begin EX_MEM_ALUOUTPUT[0] <= Ain[0] ^ Bin[0];  end
					SLT  :                                 begin
					                                       if(Ain[0] < Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 					                                       
					                                       end
					SGT  :                                 begin
					                                       if(Ain[0] > Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 								                                        
					                                       end	  
					SLE  :                                 begin
					                                       if(Ain[0] <= Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 					                                       
					                                       end					  
					SGE  :                                 begin
					                                       if(Ain[0] >= Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 					                                        
					                                       end					 
					EQ  :                                  begin
					                                       if(Ain[0] == Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 			                                       
					                                       end					 
					NEQ  :                                 begin
					                                       if(Ain[0] != Bin[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 					                                       
					                                       end					   
					MV  :                                  begin EX_MEM_ALUOUTPUT[0] <= Ain[0];  end			  	  
					ADDI :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] + ID_EX_IMM[0];  end					  
					SUBI :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] - ID_EX_IMM[0];	  end					   
					MULTI :                                begin EX_MEM_ALUOUTPUT[0] <= Ain[0] * ID_EX_IMM[0];	  end					 
					DIVI :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] / ID_EX_IMM[0];  end					 
			    ANDI :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] & ID_EX_IMM[0];	 end						  
					ORI :                                  begin EX_MEM_ALUOUTPUT[0] <= Ain[0] | ID_EX_IMM[0];	  end					 			
					XORI :                                 begin EX_MEM_ALUOUTPUT[0] <= Ain[0] ^ ID_EX_IMM[0];  end					 
					SLTI  :                                begin 
					                                       if(Ain[0] < ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 
					                                        
					                                       end
					SGTI  :                                begin 
					                                       if(Ain[0] > ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end
					                                        
					                                       end 				  
					SLEI  :                                begin 
					                                       if(Ain[0] <= ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 		
					                                        
					                                       end			  
					SGEI  :                                begin 
					                                       if(Ain[0] >= ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 	
					                                       
					                                       end				 
					EQI  :                                 begin 
					                                       if(Ain[0] == ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 
					                                        
					                                       end					 
					NEQI  :                                begin 
					                                       if(Ain[0] != ID_EX_IMM[0]) begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[0] <= 0; 
					                                       end 
					                                        
					                                       end				//REGFILE  
					MVI  :                                 begin EX_MEM_ALUOUTPUT[0] <= ID_EX_IMM[0];  end			   
					RET:                                   begin EX_MEM_ALUOUTPUT[0] <= REGFILE[31]; end					  
					NOP:                                   begin end
					HALT:                                  begin 
					                                           finish =1; 
					                                       end 
					default: begin end
			 endcase
			 
			//Computation
      case (ID_EX_OP[1])
				  LW , LB , LBU , LH:                    begin EX_MEM_ALUOUTPUT[1] <= Ain[1] + ID_EX_IMM[1];  end
				  SW , SB , SH:           	              begin EX_MEM_ALUOUTPUT[1] <= Ain[1] + ID_EX_IMM[1];  end  
					ADD  :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] + Bin[1];  end
					SUB  :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] - Bin[1];	 end	  
					MULT :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] * Bin[1];	 end					 
					DIV  : 			                             begin EX_MEM_ALUOUTPUT[1] <= Ain[1] / Bin[1];  end
			    AND  : 	                               begin EX_MEM_ALUOUTPUT[1] <= Ain[1] & Bin[1];	 end 
					OR   : 	                               begin EX_MEM_ALUOUTPUT[1] <= Ain[1] | Bin[1];	 end  	 			
					XOR  : 	                               begin EX_MEM_ALUOUTPUT[1] <= Ain[1] ^ Bin[1];  end
					SLT  :                                 begin
					                                       if(Ain[1] < Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 					                                       
					                                       end
					SGT  :                                 begin
					                                       if(Ain[1] > Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 								                                        
					                                       end	  
					SLE  :                                 begin
					                                       if(Ain[1] <= Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 					                                       
					                                       end					  
					SGE  :                                 begin
					                                       if(Ain[1] >= Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 					                                        
					                                       end					 
					EQ  :                                  begin
					                                       if(Ain[1] == Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 			                                       
					                                       end					 
					NEQ  :                                 begin
					                                       if(Ain[1] != Bin[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 					                                       
					                                       end					   
					MV  :                                  begin EX_MEM_ALUOUTPUT[1] <= Ain[1];  end			  	  
					ADDI :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] + ID_EX_IMM[1];  end					  
					SUBI :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] - ID_EX_IMM[1];	  end					   
					MULTI :                                begin EX_MEM_ALUOUTPUT[1] <= Ain[1] * ID_EX_IMM[1];	  end					 
					DIVI :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] / ID_EX_IMM[1];  end					 
			    ANDI :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] & ID_EX_IMM[1];	 end						  
					ORI :                                  begin EX_MEM_ALUOUTPUT[1] <= Ain[1] | ID_EX_IMM[1];	  end					 			
					XORI :                                 begin EX_MEM_ALUOUTPUT[1] <= Ain[1] ^ ID_EX_IMM[1];  end					 
					SLTI  :                                begin 
					                                       if(Ain[1] < ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 
					                                        
					                                       end
					SGTI  :                                begin 
					                                       if(Ain[1] > ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end
					                                        
					                                       end 				  
					SLEI  :                                begin 
					                                       if(Ain[1] <= ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 		
					                                        
					                                       end			  
					SGEI  :                                begin 
					                                       if(Ain[1] >= ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 	
					                                       
					                                       end				 
					EQI  :                                 begin 
					                                       if(Ain[1] == ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 
					                                        
					                                       end					 
					NEQI  :                                begin 
					                                       if(Ain[1] != ID_EX_IMM[1]) begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 1;
					                                       end else begin 
					                                         EX_MEM_ALUOUTPUT[1] <= 0; 
					                                       end 
					                                        
					                                       end				  
					MVI  :                                 begin EX_MEM_ALUOUTPUT[1] <= ID_EX_IMM[1];  end			   
					RET:                                   begin EX_MEM_ALUOUTPUT[1] <= REGFILE[31]; end					  
					NOP:                                   begin end
					HALT:                                  begin 
					                                           finish =1; 
					                                       end 
					default: begin end
			 endcase
			 
			 //Buffering
			 EX_MEM_IR[0] <= ID_EX_IR[0]; EX_MEM_B[0] <= Bin[0]; 
			 EX_MEM_IR[1] <= ID_EX_IR[1]; EX_MEM_B[1] <= Bin[1];
  
    //MEM STAGE
      //Computation
      if (EX_MEM_OP[0] >= LW && EX_MEM_OP[0] <= LH) MEM_WB_LMD[0] <= DMEM[EX_MEM_ALUOUTPUT[0]];
      else if (EX_MEM_OP[0] >= SW && EX_MEM_OP[0] <= SH) DMEM[EX_MEM_ALUOUTPUT[0]] <= EX_MEM_B[0];
      if (EX_MEM_OP[1] >= LW && EX_MEM_OP[1] <= LH) MEM_WB_LMD[1] <= DMEM[EX_MEM_ALUOUTPUT[1]];
      else if (EX_MEM_OP[1] >= SW && EX_MEM_OP[1] <= SH) DMEM[EX_MEM_ALUOUTPUT[1]] <= EX_MEM_B[1];
       
      //Buffering 
      MEM_WB_IR[0] <= EX_MEM_IR[0]; 
      MEM_WB_ALUOUTPUT[0] <= EX_MEM_ALUOUTPUT[0];
      MEM_WB_IR[1] <= EX_MEM_IR[1]; 
      MEM_WB_ALUOUTPUT[1] <= EX_MEM_ALUOUTPUT[1];

    //WB STAGE
      //Computation
      case(MEM_WB_OP[0])
			    ADD, SUB , MULT, DIV ,AND ,OR , XOR ,SLT,SGT ,SLE, SGE ,EQ ,   NEQ , MV : REGFILE[MEM_WB_IR[0][16:20]] <=  MEM_WB_ALUOUTPUT[0];				 
				  ADDI, SUBI , MULTI, DIVI ,ANDI ,ORI , XORI ,SLTI ,SGTI ,SLEI , SGEI ,EQI , NEQI , MVI : REGFILE[MEM_WB_IR[0][11:15]] <=  MEM_WB_ALUOUTPUT[0];    
				  LW , LB , LBU , LH :    REGFILE[MEM_WB_IR[0][11:15]] = MEM_WB_LMD[0];				     				   
		  endcase
		  
		  case(MEM_WB_OP[1])
			    ADD, SUB , MULT, DIV ,AND ,OR , XOR ,SLT,SGT ,SLE, SGE ,EQ ,   NEQ , MV : REGFILE[MEM_WB_IR[1][16:20]] <=  MEM_WB_ALUOUTPUT[1];				 
				  ADDI, SUBI , MULTI, DIVI ,ANDI ,ORI , XORI ,SLTI ,SGTI ,SLEI , SGEI ,EQI , NEQI , MVI :REGFILE[MEM_WB_IR[1][11:15]] <= MEM_WB_ALUOUTPUT[1];    
				  LW , LB , LBU , LH :    REGFILE[MEM_WB_IR[1][11:15]] = MEM_WB_LMD[1];				     				   
		  endcase
end
endmodule 