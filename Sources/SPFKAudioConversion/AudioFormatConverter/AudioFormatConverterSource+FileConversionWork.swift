// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-audio-conversion

import Foundation
import SPFKFileSystem
import SPFKUtils

extension AudioFormatConverterSource: FileConversionWork {
    public var conflictScheme: FileConflictScheme {
        get { options.conflictScheme }
        set { options.conflictScheme = newValue }
    }
}
