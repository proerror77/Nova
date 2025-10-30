//
//  CustomView518.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView518: View {
    @State public var text251Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView519(text251Text: text251Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView518_Previews: PreviewProvider {
    static var previews: some View {
        CustomView518()
    }
}
