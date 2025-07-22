// Test fixture for long variable names and values

function testLongValues() {
    // Very long variable names
    let veryLongVariableNameThatExceedsNormalLimitsForDisplay = "short value";
    let reasonableName = "This is a very long string value that should be truncated when displayed in the tree view to prevent line wrapping";
    
    // Long nested path
    let deeplyNestedObject = {
        firstLevelWithLongPropertyName: {
            secondLevelWithEvenLongerPropertyName: {
                thirdLevelWithRidiculouslyLongPropertyName: {
                    value: "deep value"
                }
            }
        }
    };
    
    // Long array with many elements
    let longArray = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
    
    // Long function name
    function thisIsAVeryLongFunctionNameThatShouldBeTruncatedInTheDisplay(param1, param2, param3) {
        return param1 + param2 + param3;
    }
    
    debugger;
}