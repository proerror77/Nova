//
//  CustomView152.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView152: View {
    @State public var text86Text: String = "Alias Accounts"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text86Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView152_Previews: PreviewProvider {
    static var previews: some View {
        CustomView152()
    }
}
