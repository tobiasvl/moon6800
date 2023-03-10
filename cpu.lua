local path = (...):match("(.-)[^%.]+$")

local bit = bit or require "bit32"
local instructions = require(path .. ".instructions")

local function register(mask)
    return setmetatable(
        {
            value = 0,
            prev_value = 0,
            prev_inst = 0,
            mask = mask or 0xFF
        },
        {
            __call = function(self, newValue)
                if newValue then
                    self.prev_value = self.value
                    self.prev_inst = num_instructions
                    self.value = bit.band(newValue, self.mask)
                else
                    return self.value
                end
            end,
            __tostring = function(self)
                return string.format(mask == 0xFF and "%02X" or "%04X", self.value)
            end
        }
    )
end

local status =
    setmetatable(
    {
        i = true -- TODO ??
    },
    {
        __call = function(self, newValue)
            if newValue then
                for _, cc in ipairs({"c", "v", "z", "n", "i", "h"}) do
                    self[cc] = bit.band(newValue, 1) == 1
                    newValue = bit.rshift(newValue, 1)
                end
            else
                local statuses = 0
                for _, cc in ipairs({"h", "i", "n", "z", "v", "c"}) do
                    statuses = bit.bor(bit.lshift(statuses, 1), self[cc] and 1 or 0)
                end
                return bit.bor(statuses, 0xC0)
            end
        end
    }
)

local CPU = {
    registers = {
        a = register(0xFF),
        b = register(0xFF),
        ix = register(0xFFFF),
        sp = register(0xFFFF),
        pc = register(0xFFFF),
        --i = register(0xFF), -- interrupt flag
        status = status
    },
    nmi = false, -- non-maskable interrupt control input
    irq = false, -- interrupt request
    key_status = {},
    screen = {}, -- TODO implement as module?
    display = true, -- TODO remove this?
    reset = true,
    instructions = {},
    breakpoint = 0
}

function CPU:init(memory)
    self.memory = memory
    instructions:init(self)

    self.reset = true
    self.instructions = 0
end

function CPU:saveToStack()
    self.memory[self.registers.sp()] = bit.band(self.registers.pc(), 0xFF)
    self.memory[self.registers.sp() - 1] = bit.rshift(self.registers.pc(), 8)
    self.memory[self.registers.sp() - 2] = bit.band(self.registers.ix(), 0xFF)
    self.memory[self.registers.sp() - 3] = bit.rshift(self.registers.ix(), 8)
    self.memory[self.registers.sp() - 4] = self.registers.a()
    self.memory[self.registers.sp() - 5] = self.registers.b()
    self.memory[self.registers.sp() - 6] = self.registers.status()
    self.registers.sp(self.registers.sp() - 7)
end

function CPU:restoreFromStack()
    self.registers.status(self.memory[self.registers.sp() + 1])
    self.registers.b(self.memory[self.registers.sp() + 2])
    self.registers.a(self.memory[self.registers.sp() + 3])
    self.registers.ix(
        bit.bor(bit.lshift(self.memory[self.registers.sp() + 4], 8), self.memory[self.registers.sp() + 5])
    )
    self.registers.pc(
        bit.bor(bit.lshift(self.memory[self.registers.sp() + 6], 8), self.memory[self.registers.sp() + 7])
    )
    self.registers.sp(self.registers.sp() + 7)
end

function CPU:fetch()
    local opcode = self.memory[self.registers.pc()]

    --print(string.format("%04X: %02X", self.registers.pc(), opcode))

    self.registers.pc(self.registers.pc() + 1)
    return opcode
end

function CPU:decode(opcode)
    if self.catch_fire then
        return {addr_mode = "inh"}
    end

    return instructions.opcodes[opcode]
end

function CPU:execute(operation)
    if not instructions[operation.addr_mode] then
        -- unimplemented opcode, treat as NOP
        self.pause = true -- TODO configurable pause
        operation = instructions.opcodes[0x01]
    end
    local addr_mode = instructions[operation.addr_mode](instructions, operation.acc)
    instructions[operation.instruction](instructions, addr_mode, operation.acc)

    --print(operation.instruction .. " " .. (operation.acc or "") .. (addr_mode() and string.format(" %04X", addr_mode()) or ""))

    return operation.cycles or 0
end

function CPU:cycle()
    if self.halt then
        if self.catch_fire then
            self:fetch()
        else -- TODO waiting != halted, so maybe move this
            if self.nmi then
                self.nmi = false
                self.registers.status.i = true -- TODO ?
                local n = 0xFFFF
                self.registers.pc(bit.band(bit.lshift(self.memory[n - 3], 8), self.memory[n - 2]))
            elseif self.irq and not self.registers.status.i then
                self.irq = false
                self.registers.status.i = true
                local n = 0xFFFF
                self.registers.pc(bit.band(bit.lshift(self.memory[n - 7], 8), self.memory[n - 6]))
            end
        end
        return 1
    else
        if self.reset then
            self.reset = false
            local n = 0xFFFF
            self.registers.pc(bit.bor(bit.lshift(self.memory[n - 1], 8), self.memory[n]))
        elseif self.nmi then
            self.nmi = false
            self:saveToStack()
            local n = 0xFFFF
            self.registers.pc(bit.bor(bit.lshift(self.memory[n - 3], 8), self.memory[n - 2]))
        elseif self.irq and not self.registers.status.i then
            self.irq = false
            self:saveToStack()
            self.registers.status.i = true
            local n = 0xFFFF
            self.registers.pc(bit.bor(bit.lshift(self.memory[n - 7], 8), self.memory[n - 6]))
        end

        local cycles = self:execute(self:decode(self:fetch()))

        if self.registers.pc() == self.breakpoint then
            self.pause = true
        end

        return cycles
    end
end

function CPU:go()
    self.halt = false
end

return CPU
