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

        it("should handle IME deleteSurroundingText and move caret correctly", function()
            InputText:initTextBox("")
            InputText:addChars("abcdef") -- charlist = {a,b,c,d,e,f}, charpos = 7
            InputText.charpos = 4 -- place caret between 'c' and 'd'
            assert.are.same({"a","b","c","d","e","f"}, InputText.charlist)
            assert.are.equal(4, InputText.charpos)

            -- delete one char to left and two to right (remove 'c','d','e')
            assert.is_true(InputText:onTextDeleteSurrounding({ left = 1, right = 2 }))
            assert.are.same({"a","b","f"}, InputText.charlist)
            assert.are.equal(3, InputText.charpos) -- caret moved to start of removed region
        end)

        it("should handle IME setSelection and move caret/selection correctly", function()
            InputText:initTextBox("")
            InputText:addChars("abcdef") -- charlist = {a..f}

            -- Android setSelection(1,3) should select chars at indices 1..2 -> InputText.selection_start_pos=2, charpos=4
            assert.is_true(InputText:onTextSelection({ start = 1, ["end"] = 3 }))
            assert.are.equal(2, InputText.selection_start_pos)
            assert.are.equal(4, InputText.charpos)

            -- collapsed selection moves caret and clears selection
            assert.is_true(InputText:onTextSelection({ start = 2, ["end"] = 2 }))
            assert.are.equal(nil, InputText.selection_start_pos)
            assert.are.equal(3, InputText.charpos)
        end)
    end)
end)
