module SoC_estimator (
    input clk,               
    input rst_n,           
    input [15:0] voltage,
    input signed [15:0] current, 
    output reg [7:0] soc   
);

parameter SOC_SCALE    = 14000;     // 1% SoC = 44μC (2000μF * 2.2V / 100)
parameter CLK_DIV 		= 50_000;        //50MHz down convert to 1ms. 
parameter V_MAX        =  65535 ;	//ADC max (700V)
parameter V_MIN        =  0		;	//ADC min (0V)
parameter C_NOM       =  2000;	//2000uF	
parameter ESR         =  1000;	//0.1 Ω
parameter I_THRESH    =  5		;//0.5A threshold (0.1A units)      

// Registers
reg [15:0] clk_cnt;              
reg [15:0] v_comp;               // ESR-compensated voltage
reg [31:0] q_accum;              // Charge accumulator (μC)
reg [7:0] soc_voltage;           // Voltage-based SoC
reg use_v_soc;                   // Control flag
wire ms_tick;

// 1ms Timer
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
		clk_cnt <= 16'b0;
    end else if(clk_cnt == CLK_DIV -1)begin
		clk_cnt <= 16'b0;
	end else begin
		clk_cnt <= clk_cnt + 1;
	end
end

assign ms_tick = (clk_cnt == CLK_DIV-1);

// ESR Voltage Compensation
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin 
		v_comp <= 16'b0;
	end else if (ms_tick) begin
        if (current > I_THRESH)begin       // Charging
            v_comp <= voltage - ((current * ESR)/1000);
		end else if (current < -I_THRESH)begin // Discharging
            v_comp <= voltage + ((-current * ESR)/1000);
        end else begin                            // Resting
            v_comp <= voltage;
		end
    end else begin
		v_comp <= voltage;							//IDLE
	end
end

// Voltage-Based SoC (when |I| < I_THRESH)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
		soc_voltage <= 8'b0;
	end else if (ms_tick) begin
        if (v_comp >= V_MAX)begin 
			soc_voltage <= 100;
        end else if (v_comp <= V_MIN)begin 
			soc_voltage <= 0;
        end else begin
			soc_voltage <= ((v_comp - V_MIN) * 100) / (V_MAX - V_MIN);
		end
    end else begin
		soc_voltage <= soc_voltage;
	end
end

// Coulomb Counting & Hybrid Logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        q_accum <= 0;
        use_v_soc <= 1;
    end else if (ms_tick) begin
        if (current > -I_THRESH && current < I_THRESH) begin
            // Update from voltage when resting
            q_accum <= soc_voltage * SOC_SCALE;
            use_v_soc <= 1;
        end else begin
            // Accumulate charge: ΔQ = I (mA) × 1ms = 1μC
            q_accum <= q_accum + (current*100);
            use_v_soc <= 0;
        end
    end
end

// Final SoC Calculation
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)begin
		soc <= 0;
	end else if (ms_tick) begin
        if (use_v_soc) begin
            soc <= soc_voltage;  // Direct voltage-based
        end else begin
            // Calculate from accumulated charge
            if (q_accum >= 100 * SOC_SCALE)begin
				soc <= 100;
            end else if (q_accum <= 0)begin 
				soc <= 0;
            end else begin
				soc <= q_accum / SOC_SCALE;
			end
        end
    end
end

endmodule