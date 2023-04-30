module mipspipe_mp3 (clock);
  // in_out
  input clock;

  // Instruction opcodes
  parameter LW = 6'b100011, SW = 6'b101011, BEQ = 6'b000100, nop = 32'b00000_100000, ALUop = 6'b0;
  reg [31:0] PC, Regs[0:31], IMemory[0:1023], DMemory[0:1023], // instruction and data memories
             IFIDIR, IDEXA, IDEXB, IDEXIR, EXMEMIR, EXMEMB, // pipeline latches
             EXMEMALUOut, MEMWBValue, MEMWBIR;

  wire [4:0] IDEXrs, IDEXrt, EXMEMrd, MEMWBrd, MEMWBrt; // hold register fields
  wire [5:0] EXMEMop, MEMWBop, IDEXop; // hold opcodes
  wire [31:0] Ain, Bin; // ALU inputs

  // declare the bypass signals
  wire bypassAfromMEM, bypassAfromALUinWB, bypassBfromMEM, bypassBfromALUinWB, bypassAfromLWinWB, bypassBfromLWinWB;

  // Define fields of pipeline latches
  assign IDEXrs = IDEXIR[25:21]; // rs field
  assign IDEXrt = IDEXIR[20:16]; // rt field
  assign EXMEMrd = EXMEMIR[15:11]; // rd field
  assign MEMWBrd = MEMWBIR[15:11]; // rd field
  assign MEMWBrt = MEMWBIR[20:16]; // rt field -- for loads
  assign EXMEMop = EXMEMIR[31:26]; // opcode
  assign MEMWBop = MEMWBIR[31:26]; // opcode
  assign IDEXop = IDEXIR[31:26]; // opcode

  // The bypass to input A from the MEM stage for an ALU operation
  assign bypassAfromMEM = (IDEXrs == EXMEMrd) & (IDEXrs != 0) & (EXMEMop == ALUop);
  // The bypass to input B from the MEM stage for an ALU operation
  assign bypassBfromMEM = (IDEXrt == EXMEMrd) & (IDEXrt != 0) & (EXMEMop == ALUop);
  // The bypass to input A from the WB stage for an ALU operation
  assign bypassAfromALUinWB = (IDEXrs == MEMWBrd) & (IDEXrs != 0) & (MEMWBop == ALUop);
  // The bypass to input B from the WB stage for an ALU operation
  assign bypassBfromALUinWB = (IDEXrt == MEMWBrd) & (IDEXrt != 0) & (MEMWBop == ALUop);
  // The bypass to input A from the WB stage for an LW operation
  assign bypassAfromLWinWB = (IDEXrs == MEMWBIR[20:16]) & (IDEXrs != 0) & (MEMWBop == LW);
  // The bypass to input B from the WB stage for an LW operation
  assign bypassBfromLWinWB = (IDEXrt == MEMWBIR[20:16]) & (IDEXrt != 0) & (MEMWBop == LW);

  // The A input to the ALU is bypassed from MEM if there is a bypass there,
  // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
  assign Ain = bypassAfromMEM ? EXMEMALUOut : (bypassAfromALUinWB | bypassAfromLWinWB) ? MEMWBValue : IDEXA;

  // The B input to the ALU is bypassed from MEM if there is a bypass there,
  // Otherwise from WB if there is a bypass there, and otherwise comes from the IDEX register
  assign Bin = bypassBfromMEM ? EXMEMALUOut : (bypassBfromALUinWB | bypassBfromLWinWB) ? MEMWBValue : IDEXB;

  reg [5:0] i; // used to initialize latches
  reg [10:0] j, k; // used to initialize memories
  
  initial begin
    PC = 0;
    IFIDIR = nop; 
    IDEXIR = nop; 
    EXMEMIR = nop; 
    MEMWBIR = nop; // no-ops in pipeline latches
  
    for (i = 0; i <= 31; i = i + 1) Regs[i] = i; // initialize latches
  
    IMemory[0] = 32'h00412820;
    IMemory[1] = 32'h8ca30004;
    IMemory[2] = 32'haca70005;
    IMemory[3] = 32'h00602020;
    IMemory[4] = 32'h01093020;
    IMemory[5] = 32'hac06000c;  
    IMemory[6] = 32'h00c05020;
    IMemory[7] = 32'h8c0b0010;
    IMemory[8] = 32'h00000020;  
    IMemory[9] = 32'h002b6020;
    for (j = 10; j <= 1023; j = j + 1) IMemory[j] = nop;
    
    DMemory[0] = 32'h00000000;
    DMemory[1] = 32'hffffffff;
    DMemory[2] = 32'h00000000;
    DMemory[3] = 32'h00000000;
    DMemory[4] = 32'hfffffffe;
    for (k = 5; k <= 1023; k = k + 1) DMemory[k] = 0;
  end

  always @ (posedge clock) 
  begin
    
    // FETCH: Fetch instruction & update PC
    IFIDIR <= IMemory[PC>>2];
    PC <= PC + 4;

    // DECODE: Read registers
    IDEXA <= Regs[IFIDIR[25:21]]; 
    IDEXB <= Regs[IFIDIR[20:16]];
    IDEXIR <= IFIDIR; 

    // EX: Address calculation or ALU operation
    if ((IDEXop == LW) | (IDEXop == SW)) // address calculation & copy B
      EXMEMALUOut <= Ain + {{16{IDEXIR[15]}}, IDEXIR[15:0]};
    else if (IDEXop == ALUop) begin
      case (IDEXIR[5:0]) // R-type instruction
      // ALU operations
      6'b100000: EXMEMALUOut <= Ain + Bin; // add
      6'b100010: EXMEMALUOut <= Ain - Bin; // sub
      6'b100100: EXMEMALUOut <= Ain & Bin; // and
      6'b100101: EXMEMALUOut <= Ain | Bin; // or
      6'b101010: EXMEMALUOut <= (Ain < Bin) ? 1 : 0; // slt
      default:   EXMEMALUOut <= Ain + Bin; // default to add
      endcase
    end
    EXMEMIR <= IDEXIR;
    EXMEMB <= IDEXB;

    // MEM: Read or write data memory
    if (EXMEMop == LW)
      MEMWBValue <= DMemory[EXMEMALUOut[10:2]];
    else if (EXMEMop == SW)
      DMemory[EXMEMALUOut[10:2]] <= EXMEMB;
    MEMWBIR <= EXMEMIR;

    // WB: Write back to register file
    if (MEMWBop == ALUop)
      Regs[MEMWBrd] <= MEMWBValue;
    else if (MEMWBop == LW)
      Regs[MEMWBrt] <= MEMWBValue;
  end
endmodule



