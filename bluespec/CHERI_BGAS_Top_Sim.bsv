package CHERI_BGAS_Top_Sim;

import FIFOF :: *;
import AXI4 :: *;
import AXI4Lite :: *;
import AXI4_AXI4Lite_Bridges :: *;
import BlueUtils :: *;
import SourceSink :: *;
import Connectable :: *;
import CHERI_BGAS_Top :: *;
import DE10Pro_bsv_shell :: *;
import Recipe :: *;

// Concrete parameters definitions
// -------------------------------

`define H2F_LW_ADDR   21 // from 20 (1MB) to 21 (2MB)
`define H2F_LW_DATA   32
`define H2F_LW_AWUSER  0
`define H2F_LW_WUSER   0
`define H2F_LW_BUSER   0
`define H2F_LW_ARUSER  0
`define H2F_LW_RUSER   0

`define H2F_ID       4
`define H2F_ADDR    32 // from 20 (1MB) to 32 (4GB)
`define H2F_DATA   128 // 32, 64 or 128
`define H2F_AWUSER   0
`define H2F_WUSER    0
`define H2F_BUSER    0
`define H2F_ARUSER   0
`define H2F_RUSER    0

`define F2H_ID       4
`define F2H_ADDR    32 // from 20 (1MB) to 40 (1TB)
`define F2H_DATA   128
`define F2H_AWUSER   0
`define F2H_WUSER    0
`define F2H_BUSER    0
`define F2H_ARUSER   0
`define F2H_RUSER    0

// DDR AXI ports parameters

`define DRAM_ID       8
`define DRAM_ADDR    32
`define DRAM_DATA   128
`define DRAM_AWUSER   0
`define DRAM_WUSER    0
`define DRAM_BUSER    0
`define DRAM_ARUSER   0
`define DRAM_RUSER    0

// AXI4Lite control port driver
////////////////////////////////////////////////////////////////////////////////

module mkDriveAXILite (AXI4Lite_Master #( `H2F_LW_ADDR
                                        , `H2F_LW_DATA
                                        , `H2F_LW_AWUSER
                                        , `H2F_LW_WUSER
                                        , `H2F_LW_BUSER
                                        , `H2F_LW_ARUSER
                                        , `H2F_LW_RUSER ));

  // general helpers
  //////////////////////////////////////////////////////////////////////////////

  let delayReg <- mkRegU;
  function recipeDelay (delay) = rSeq ( rBlock (
    action delayReg <= delay; endaction
    , rWhile ( delayReg > 0, rAct ( action delayReg <= delayReg - 1; endaction))
  ));

  let shim <- mkAXI4LiteShim;

  let readRegRes <- mkRegU; // reg used by reads and writes for return values.
                            // Must be explicitly handled by the caller

  function readReg (verbosity, addr) = rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting readReg, addr = "
                             , $time
                             , fshow (addr))))
    , shim.slave.ar.put (AXI4Lite_ARFlit { araddr: addr
                                         , arprot: 0
                                         , aruser: 0 })
    , action
        let val <- get (shim.slave.r);
        readRegRes <= val.rdata;
      endaction
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended readReg, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );
  function writeReg (verbosity, addr, data) = rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting writeReg, addr = "
                             , $time
                             , fshow (addr)
                             , ", data = "
                             , fshow (data))))
    , action
        shim.slave.aw.put (AXI4Lite_AWFlit { awaddr: addr
                                           , awprot: 0
                                           , awuser: 0 });
        shim.slave.w.put (AXI4Lite_WFlit { wdata: data
                                         , wstrb: ~0
                                         , wuser: 0 });
      endaction
    , shim.slave.b.drop
    , rWhen ( verbosity > 0
            , rAct ($display ("%0t - Ended writeReg", $time)))
    ) );

  // Debug unit helpers
  //////////////////////////////////////////////////////////////////////////////

  let debugBaseAddr = 32'hf9000000;
  function debugUnitReadReg (verbosity, idx) =
    readReg (verbosity, debugBaseAddr + zeroExtend ({idx, 2'b00}));
  function debugUnitWriteReg (verbosity, idx, data) =
    writeReg (verbosity, debugBaseAddr + zeroExtend ({idx, 2'b00}), data);

  function Recipe debugUnitSendHalt (Integer verbosity) =
    rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting debugUnitSendHalt"
                             , $time )))
    , debugUnitWriteReg (verbosity - 1, 7'h10, 'h80000001)
    , debugUnitReadReg (verbosity - 1, 7'h11)
    , rWhile ( readRegRes[8] == 1'b0
             , debugUnitReadReg (verbosity - 1, 7'h11) )
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended debugUnitSendHalt, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );

  function Recipe debugUnitSendResume (Integer verbosity) =
    rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting debugUnitSendResume"
                             , $time )))
    , debugUnitWriteReg (verbosity - 1, 7'h10, 'h40000001)
    , debugUnitReadReg (verbosity - 1, 7'h11)
    , rWhile ( readRegRes[10] == 1'b0
             , debugUnitReadReg (verbosity - 1, 7'h11) )
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended debugUnitSendResume, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );

  function Recipe debugUnitSendReset (Integer verbosity, Bool running) =
    rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting debugUnitSendReset, running = "
                             , $time
                             , fshow (running))))
    , debugUnitSendHalt (verbosity - 1)
    , debugUnitWriteReg (verbosity - 1, 7'h10, running ? 'h00000003 : 'h80000003)
    , recipeDelay (5)
    , debugUnitWriteReg (verbosity - 1, 7'h10, running ? 'h00000001 : 'h80000001)
    , recipeDelay (500)
    , debugUnitReadReg (verbosity - 1, 7'h11)
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended debugUnitSendReset, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );

  function Recipe debugUnitSendMemRead (Integer verbosity, Bit #(64) addr) =
    rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting debugUnitSendMemRead, addr = "
                             , $time
                             , fshow (addr))))
    , debugUnitWriteReg (verbosity - 1, 7'h17, 'h003207b0)
    , debugUnitWriteReg (verbosity - 1, 7'h38, 'h00150000)
    , debugUnitWriteReg (verbosity - 1, 7'h3a, truncateLSB (addr))
    , debugUnitWriteReg (verbosity - 1, 7'h39, truncate (addr))
    , debugUnitReadReg (verbosity - 1, 7'h3c)
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended debugUnitSendMemRead, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );

  function Recipe debugUnitSendMemWrite ( Integer verbosity
                                      , Bit #(64) addr
                                      , Bit #(32) data) =
    rSeq ( rBlock (
      rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Starting debugUnitSendMemWrite, addr = "
                             , $time
                             , fshow (addr)
                             , ", data = "
                             , fshow (data))))
    , debugUnitWriteReg (verbosity - 1, 7'h17, 'h003207b0)
    , debugUnitWriteReg (verbosity - 1, 7'h38, 'h00050000)
    , debugUnitWriteReg (verbosity - 1, 7'h3a, truncateLSB (addr))
    , debugUnitWriteReg (verbosity - 1, 7'h39, truncate (addr))
    , debugUnitWriteReg (verbosity - 1, 7'h3c, data)
    , debugUnitReadReg (verbosity - 1, 7'h38)
    , rWhen ( verbosity > 0
            , rAct ($display ( "%0t - Ended debugUnitSendMemWrite, value returned = "
                             , $time
                             , fshow (readRegRes))))
    ) );

  // fake 16550 helpers
  //////////////////////////////////////////////////////////////////////////////

  let fake16550BaseAddr = 32'hf9030000;
  function fake16550ReadReg (verbosity, idx) =
    readReg (verbosity, fake16550BaseAddr + zeroExtend (idx));
  function fake16550WriteReg (verbosity, idx, data) =
    writeReg (verbosity, fake16550BaseAddr + zeroExtend (idx), data);
  function fake16550ReceiveData (verbosity) =
    readReg (verbosity, fake16550BaseAddr + zeroExtend (4'h0));
  function fake16550TransmitData (verbosity, data) =
    writeReg (verbosity, fake16550BaseAddr + zeroExtend (4'h0), data);

  // Instantiate top recipe
  //////////////////////////////////////////////////////////////////////////////

  Integer verbosity = 2;
  PulseWire done <- mkPulseWire;
  //Recipe r = rSeq ( rBlock (
  //    debugUnitSendReset (verbosity, False)
  //  //, debugUnitSendMemWrite (verbosity, 'h80008000, 'hdeadbeef)
  //  //, debugUnitSendMemRead (verbosity, 'h80008000)
  //  , done.send
  //  ));
  //Recipe r = rSeq ( rBlock (
  //    debugUnitSendReset (verbosity, False)
  //  , debugUnitWriteReg (verbosity, 7'h10, 'h3)
  //  , debugUnitWriteReg (verbosity, 7'h10, 'h80000001)
  //  , debugUnitWriteReg (verbosity, 7'h17, 'h003207b0)
  //  , debugUnitReadReg (verbosity, 7'h16)
  //  , debugUnitReadReg (verbosity, 7'h4)
  //  , debugUnitWriteReg (verbosity, 7'h4, 'h4000b0d3)
  //  , debugUnitWriteReg (verbosity, 7'h5, 'h0)
  //  , debugUnitWriteReg (verbosity, 7'h17, 'h003307b0)
  //  , debugUnitReadReg (verbosity, 7'h16)
  //  , done.send
  //  ));
  //let core_uart_addr = 'h_6230_0000;
  //Recipe r = rSeq ( rBlock (
  //    recipeDelay (2000)
  //  , debugUnitSendReset (verbosity, False)
  //  , fake16550TransmitData (verbosity, 'hdeadbeef)
  //  , debugUnitSendMemRead (verbosity, core_uart_addr)
  //  , debugUnitSendMemWrite (verbosity, core_uart_addr, 'hb00bf00d)
  //  , fake16550ReceiveData (verbosity)
  //  , done.send
  //  ));
  //Recipe r = rSeq ( rBlock (
  //    recipeDelay (2000)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendResume (verbosity)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendResume (verbosity)
  //  , debugUnitSendReset (verbosity, False)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendResume (verbosity)
  //  , debugUnitSendReset (verbosity, False)
  //  , debugUnitSendResume (verbosity)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendReset (verbosity, True)
  //  , debugUnitSendResume (verbosity)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendReset (verbosity, True)
  //  , debugUnitSendHalt (verbosity)
  //  , debugUnitSendResume (verbosity)
  //  , done.send
  //  ));
  Recipe r = rSeq ( rBlock (
      //recipeDelay (450000)
      recipeDelay (1000)
    , debugUnitWriteReg (verbosity, 7'h10, 'h80000001)
    , debugUnitReadReg (verbosity, 7'h11) // expected value: 382
    , debugUnitWriteReg (verbosity, 7'h17, 'h3207b0)
    , recipeDelay (1000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2 got: 1002 <--- he 1 is for "busy"
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 400000d3
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h4, 'h4000b0d3)
    , debugUnitWriteReg (verbosity, 7'h5, 'h0)
    , debugUnitWriteReg (verbosity, 7'h17, 'h3307b0)
    , recipeDelay (1000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2 got: 1002
    , debugUnitReadReg (verbosity, 7'h11) // expected value: 382
    , debugUnitWriteReg (verbosity, 7'h17, 'h3207b0)
    , recipeDelay (1000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2 got 1002
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 4000b0d3
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    /*
    , debugUnitWriteReg (verbosity, 7'h17, 'h321000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321001)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321002)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321003)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321004)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321005)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321006)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321007)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321008)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321009)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100a)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100b)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100c)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100d)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100e)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100f)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321010)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321011)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321012)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321013)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321014)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321015)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321016)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321017)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321018)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321019)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101a)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101b)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101c)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101d)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101e)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101f)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    */
    , debugUnitWriteReg (verbosity, 7'h17, 'h3207b1)
    , recipeDelay (1000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2 got 1002
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 70000000
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 20040807
    , debugUnitWriteReg (verbosity, 7'h38, 'h20457000)
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 20050807
    , debugUnitWriteReg (verbosity, 7'h3a, 'h0)
    , debugUnitWriteReg (verbosity, 7'h39, 'hc0000000)
    , debugUnitWriteReg (verbosity, 7'h3c, 'hdeadbeef)
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 20050807
    /*
    , debugUnitWriteReg (verbosity, 7'h17, 'h321000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321001)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321002)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321003)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321004)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321005)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321006)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321007)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321008)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321009)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100a)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100b)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100c)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100d)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100e)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32100f)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321010)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321011)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321012)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321013)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321014)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321015)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321016)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321017)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321018)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h321019)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101a)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101b)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101c)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101d)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101e)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitWriteReg (verbosity, 7'h17, 'h32101f)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    */
    , debugUnitWriteReg (verbosity, 7'h17, 'h3207b1)
    , recipeDelay (1000)
    , debugUnitReadReg (verbosity, 7'h16) // expected value: 2 got 1002
    , debugUnitReadReg (verbosity, 7'h4) // expected value: 70000000
    , debugUnitReadReg (verbosity, 7'h5) // expected value: 0
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 20050807
    , debugUnitWriteReg (verbosity, 7'h38, 'h2055f000)
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 2015b807 got: 20158807
    , debugUnitWriteReg (verbosity, 7'h3a, 'h0)
    , debugUnitWriteReg (verbosity, 7'h39, 'hc0000000)
    , debugUnitReadReg (verbosity, 7'h38) // expected value: 2015b807 got: 20158807 <--- the b says align error, only shows in hardware, not in sim...
    , debugUnitReadReg (verbosity, 7'h3c) // expected value: 0
    , done.send
    ));
  RecipeFSM m <- mkRecipeFSM (r);
  // Start runing the recipe
  rule run;
    $display("starting at time %0t", $time);
    $display("------------------------------------------");
    m.trigger;
  endrule

  // On the recipe's last cyle, terminate simulation
  rule endSim (done);
    $display("------------------------------------------");
    $display("finishing at time %0t", $time);
    $finish(0);
  endrule
  return debugAXI4Lite_Master ( truncateAddrFieldsMasterLite (shim.master)
                              , $format ("axilite driver"));
endmodule

// AXI4 fake DDR
////////////////////////////////////////////////////////////////////////////////

module mkFakeDDR (AXI4_Slave #( `DRAM_ID
                              , `DRAM_ADDR
                              , `DRAM_DATA
                              , `DRAM_AWUSER
                              , `DRAM_WUSER
                              , `DRAM_BUSER
                              , `DRAM_ARUSER
                              , `DRAM_RUSER ));

  Integer verbosity = 2;
  //let memLite <- mkAXI4LiteMem ('hffffffff, Invalid);
  //return debugAXI4_Slave (fromAXI4LiteToAXI4_Slave (memLite), $format ("fake ddr"));
  let rFF <- mkUGFIFOF;
  let rFlits <- mkReg (0);
  let awFF <- mkUGFIFOF;
  let wFF <- mkUGFIFOF;
  let wFlits <- mkReg (0);
  let allTheMemoryInTheWorld <- mkRegU;
  interface Sink ar;
    method canPut = rFF.notFull;
    method put = rFF.enq;
  endinterface
  interface Source r;
    method canPeek = rFF.notEmpty;
    method peek = AXI4_RFlit { rid: rFF.first.arid
                             , rresp: OKAY
                             , rdata: allTheMemoryInTheWorld
                             , rlast: (rFF.first.arlen == rFlits)
                             , ruser: 0 };
    method drop = action
      $display ("%0t - mkFakeDDR answers ", $time, fshow (rFF.first));
      if (rFF.first.arlen == rFlits) begin
        $display ("%0t - mkFakeDDR consumes ", $time, fshow (rFF.first));
        rFF.deq;
        rFlits <= 0;
      end else rFlits <= rFlits + 1;
    endaction;
  endinterface
  interface Sink aw;
    method canPut = awFF.notFull;
    method put = awFF.enq;
  endinterface
  interface Sink w;
    method canPut = wFF.notFull;
    method put (x) = action
      wFF.enq (x);
      allTheMemoryInTheWorld <= x.wdata;
    endaction;
  endinterface
  interface Source b;
    method canPeek = awFF.notEmpty && wFF.notEmpty;
    method peek = AXI4_BFlit { bid: awFF.first.awid
                             , bresp: OKAY
                             , buser: 0 };
    method drop = action
      if (awFF.first.awlen == wFlits) begin
        $display ("%0t - mkFakeDDR consumes ", $time, fshow (awFF.first));
        awFF.deq;
        wFlits <= 0;
      end else wFlits <= wFlits + 1;
      wFF.deq;
      $display ("%0t - mkFakeDDR consumes ", $time, fshow (wFF.first));
    endaction;
  endinterface

endmodule

// Simulation toplevel module
////////////////////////////////////////////////////////////////////////////////

module mkCHERI_BGAS_Top_Sim (Empty);
  DE10ProIfc cheri_bgas_top <- mkCHERI_BGAS_Top;
  AXI4Lite_Master #( `H2F_LW_ADDR
                   , `H2F_LW_DATA
                   , `H2F_LW_AWUSER
                   , `H2F_LW_WUSER
                   , `H2F_LW_BUSER
                   , `H2F_LW_ARUSER
                   , `H2F_LW_RUSER ) axiLiteDriver <- mkDriveAXILite;
  AXI4_Slave #( `DRAM_ID
              , `DRAM_ADDR
              , `DRAM_DATA
              , `DRAM_AWUSER
              , `DRAM_WUSER
              , `DRAM_BUSER
              , `DRAM_ARUSER
              , `DRAM_RUSER ) fakeDDRB <- mkFakeDDR;

  mkConnection (cheri_bgas_top.axls_h2f_lw, axiLiteDriver);
  //mkConnection (cheri_bgas_top.axs_h2f, culDeSac);
  //mkConnection (cheri_bgas_top.axm_f2h, culDeSac);
  mkConnection (cheri_bgas_top.axm_ddrb, fakeDDRB);
  //mkConnection (cheri_bgas_top.axm_ddrc, culDeSac);
  //mkConnection (cheri_bgas_top.axm_ddrd, culDeSac);
endmodule

endpackage
