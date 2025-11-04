//
//  CustomView201.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView201: View {
    @State public var text104Text: String = "Cancel"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text104Text)
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 14))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 44, height: 20, alignment: .topLeading)
    }
}

struct CustomView201_Previews: PreviewProvider {
    static var previews: some View {
        CustomView201()
    }
}
