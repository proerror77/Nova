//
//  CustomView50.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView50: View {
    @State public var text23Text: String = "view more"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView51(text23Text: text23Text)
                .frame(width: 60.153, height: 17)
        }
        .frame(width: 60.153, height: 17, alignment: .topLeading)
    }
}

struct CustomView50_Previews: PreviewProvider {
    static var previews: some View {
        CustomView50()
    }
}
