describe("InputText widget module", function()
    local InputText
    local equals
    setup(function()
        require("commonrequire")
        InputText = require("ui/widget/inputtext"):new{}

        equals = require("util").tableEquals
    end)

    describe("addChars()", function()
        it("should add regular text", function()
            InputText:initTextBox("")
            InputText:addChars("a")
            assert.is_true( equals({"a"}, InputText.charlist) )
            InputText:addChars("aa")
            assert.is_true( equals({"a", "a", "a"}, InputText.charlist) )
        end)
        it("should add unicode text", function()
            InputText:initTextBox("")
            InputText:addChars("Л")
            assert.is_true( equals({"Л"}, InputText.charlist) )
            InputText:addChars("Луа")
            assert.is_true( equals({"Л", "Л", "у", "а"}, InputText.charlist) )
        end)

        it("should accept IME composition updates and map Android cursor correctly", function()
            -- simulate an IME preedit update: text contains 2 chars, Android cursor position p=1 (means cursor at end)
            InputText:initTextBox("")
            local comp = { text = "あい", cursor = 1, finished = false }
            assert.is_true(InputText:onTextComposition(comp))
            -- composition_text must be set and composition_cursor normalized to 3 (L+1)
            assert.is_true(InputText.composition_active)
            assert.are.equal("あい", InputText.composition_text)
            assert.are.equal(3, tonumber(InputText.composition_cursor))

            -- commit it multiple times (simulate repeated IME commits)
            InputText:onTextInput("あい")
            assert.are.same({"あ","い"}, InputText.charlist)

            -- simulate another composition + commit
            comp = { text = "ertf", cursor = 1, finished = false }
            assert.is_true(InputText:onTextComposition(comp))
            InputText:onTextInput("ertf")
            assert.are.same({"あ","い","e","r","t","f"}, InputText.charlist)
        end)

        it("should insert committed IME text into charlist via onTextInput", function()
            InputText:initTextBox("")
            InputText:onTextInput("漢字")
            assert.is_true( equals({"漢","字"}, InputText.charlist) )
        end)
    end)
end)
