local path = ...

return {
    cpu = require(path .. ".cpu"),
    bus = require(path .. ".memory"),
    disassembler = require(path .. ".disassembler"),
    instructions = require(path .. ".instructions"),
    opcodes = require(path .. ".opcodes"),
    ram = require(path .. ".ram"),
    eprom = require(path .. ".eprom")
}
