//
//  CustomView403.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView403: View {
    @State public var image258Path: String = "image258_41321"
    @State public var text216Text: String = "Search"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CustomView404(
                image258Path: image258Path,
                text216Text: text216Text)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .frame(width: 349, height: 32, alignment: .topLeading)
        .background(Color(red: 0.89, green: 0.88, blue: 0.87, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

struct CustomView403_Previews: PreviewProvider {
    static var previews: some View {
        CustomView403()
    }
}
