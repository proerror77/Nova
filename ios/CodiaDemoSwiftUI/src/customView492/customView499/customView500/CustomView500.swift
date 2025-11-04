//
//  CustomView500.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView500: View {
    @State public var text245Text: String = "Uh-huh..."
    @State public var image311Path: String = "image311_41601"
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            CustomView501(text245Text: text245Text)
                .frame(width: 111, height: 46)
            Image(image311Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50, alignment: .topLeading)
                .cornerRadius(25)
        }
        .frame(width: 167, height: 50, alignment: .top)
    }
}

struct CustomView500_Previews: PreviewProvider {
    static var previews: some View {
        CustomView500()
    }
}
